#
# Copyright (c) 2009-2011 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'fileutils'
require File.normalize_path(File.join(File.dirname(__FILE__), 'json_utilities'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'feature_config_manager'))

module RightScale

  # Manages instance state
  class InstanceState
    # States that are recorded in a standard fashion and audited when transitioned to
    RECORDED_STATES = %w{ booting operational stranded decommissioning }

    # States that cause the system MOTD/banner to indicate that everything is OK
    SUCCESSFUL_STATES = %w{ operational }

    # States that cause the system MOTD/banner to indicate that something is wrong
    FAILED_STATES = %w{ stranded }

    # Initial state prior to booting
    INITIAL_STATE = 'pending'

    # Final state when shutting down that is recorded in a non-standard fashion
    FINAL_STATE = 'decommissioned'

    # Valid internal states
    STATES = RECORDED_STATES + [FINAL_STATE]

    # Path to JSON file where current instance state is serialized
    STATE_DIR = AgentConfig.agent_state_dir
    STATE_FILE = File.join(STATE_DIR, 'state.js')

    # Path to JSON file where authorized login users are defined
    LOGIN_POLICY_FILE = File.join(STATE_DIR, 'login_policy.js')

    # Path to boot log
    BOOT_LOG_FILE = File.join(RightScale::Platform.filesystem.log_dir, 'install')

    # Path to decommission log
    DECOMMISSION_LOG_FILE = File.join(RightScale::Platform.filesystem.log_dir, 'decommission')

    # Number of seconds to wait for cloud to shutdown instance
    FORCE_SHUTDOWN_DELAY = 180

    # Maximum number of retries to record state with RightNet
    MAX_RECORD_STATE_RETRIES = 5

    # Number of seconds between attempts to record state
    RETRY_RECORD_STATE_DELAY = 5

    # Minimum interval in seconds for persistent storage of last communication
    LAST_COMMUNICATION_STORAGE_INTERVAL = 2

    # State for recording progress of planned volume management.
    class PlannedVolumeState
      attr_accessor :disks, :mappings, :volumes
    end

    # (String) One of STATES
    def self.value
      @value
    end

    # (String) One of STATES
    def self.last_recorded_value
      @last_recorded_value
    end

    # (RetryableRequest) Current record state request
    def self.record_request
      @record_request
    end

    # (String) Instance agent identity
    def self.identity
      @identity
    end

    # (LoginPolicy) The most recently enacted login policy
    def self.login_policy
      @login_policy
    end

    # Queries most recent state of planned volume mappings.
    #
    # === Return
    # result(Array):: persisted mappings or empty
    def self.planned_volume_state
      @planned_volume_state ||= PlannedVolumeState.new
    end

    # (String) Type of decommission currently in progress or nil
    def self.decommission_type
      if @value == 'decommissioning' || @value == 'decommissioned'
        @decommission_type
      else
        raise RightScale::Exceptions::WrongState.new("Unexpected call to InstanceState.decommission_type for current state #{@value.inspect}")
      end
    end

    # Set instance id with given id
    # Load persisted state if any, compare instance ids and force boot if instance ID
    # is different or if reboot flagged
    # For reboot detection relying on rightboot script in linux and shutdown notification in windows
    # to update the reboot flag in the state file
    #
    # === Parameters
    # identity(String):: Instance identity
    # read_only(Boolean):: Whether only allowed to read the instance state, defaults to false
    #
    # === Return
    # true:: Always return true
    def self.init(identity, read_only = false)
      @identity = identity
      @read_only = read_only
      @startup_tags = []
      @log_level = Logger::INFO
      @initial_boot = false
      @reboot = false
      @resource_uid = nil
      @last_recorded_value = nil
      @record_retries = 0
      @record_request = nil
      @record_timer = nil
      @last_communication = 0
      @planned_volume_state = nil
      @decommission_type = nil

      unless @read_only
        Log.notify(lambda { |l| @log_level = l })
        Sender.instance.message_received { communicated }
        RightHttpClient.communicated([:auth, :api]) { communicated } rescue nil # because not applicable in AMQP mode
      end

      # need to grab the current resource uid whether there is a state file or not.
      @resource_uid = current_resource_uid

      dir = File.dirname(STATE_FILE)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
      if File.file?(STATE_FILE)
        state = RightScale::JsonUtilities::read_json(STATE_FILE)
        Log.debug("Initializing instance #{identity} with #{state.inspect}")

        # Initial state reconciliation: use recorded state and boot timestamp to determine how we last stopped.
        # There are four basic scenarios to worry about:
        #  1) first run          -- Agent is starting up for the first time after a fresh install
        #  2) reboot/restart     -- Agent already ran; agent ID not changed; reboot detected: transition back to booting
        #  3) bundled boot       -- Agent already ran; agent ID changed: transition back to booting
        #  4) decommission/crash -- Agent exited anyway; ID not changed; no reboot; keep old state entirely
        #  5) ec2 restart        -- Agent already ran; agent ID changed; instance ID is the same; transition back to booting
        if state['identity'] && state['identity'] != identity && !@read_only
          @last_recorded_value = state['last_recorded_value']
          self.value = 'booting'
          # if the current resource_uid is the same as the last
          # observed resource_uid, then this is a restart,
          # otherwise this is a bundle
          old_resource_uid = state["last_observed_resource_uid"]
          if @resource_uid && @resource_uid == old_resource_uid
            # CASE 5 -- identity has changed; ec2 restart
            Log.debug("Restart detected; transitioning state to booting")
            @reboot = true
          else
            # CASE 3 -- identity has changed; bundled boot
            Log.debug("Bundle detected; transitioning state to booting")
          end
        elsif state['reboot'] && !@read_only
          # CASE 2 -- rebooting flagged by rightboot script in linux or by shutdown notification in windows
          Log.debug("Reboot detected; transitioning state to booting")
          @last_recorded_value = state['last_recorded_value']
          self.value = 'booting'
          @reboot = true
        else
          # CASE 4 -- restart without reboot; continue with retries if recorded state does not match
          @value = state['value']
          @reboot = state['reboot']
          @startup_tags = state['startup_tags']
          @log_level = state['log_level']
          @last_recorded_value = state['last_recorded_value']
          @record_retries = state['record_retries']
          @decommission_type = state['decommission_type'] if (@value == 'decommissioning' || @value == 'decommissioned')
          if @value != @last_recorded_value && RECORDED_STATES.include?(@value) &&
             @record_retries < MAX_RECORD_STATE_RETRIES && !@read_only
            record_state
          else
            @record_retries = 0
          end
          update_logger
        end
      else
        # CASE 1 -- state file does not exist; initial boot, create state file
        Log.debug("Initializing instance #{identity} with booting")
        @last_recorded_value = INITIAL_STATE
        self.value = 'booting'
        @initial_boot = true
      end

      if File.file?(LOGIN_POLICY_FILE)
        @login_policy = RightScale::JsonUtilities::read_json(LOGIN_POLICY_FILE) rescue nil #corrupt file here is not important enough to fail
      else
        @login_policy = nil
      end
      Log.debug("Existing login users: #{@login_policy.users.length} recorded") if @login_policy

      #Ensure MOTD is up to date
      update_motd

      true
    end

    # Set instance state
    #
    # === Parameters
    # val(String) One of STATES
    #
    # === Return
    # val(String) new state
    #
    # === Raise
    # RightScale::Exceptions::Application:: Cannot update in read-only mode
    # ArgumentError:: Invalid new value
    def self.value=(val)
      previous_val = @value || INITIAL_STATE
      raise RightScale::Exceptions::Application, "Not allowed to modify instance state in read-only mode" if @read_only
      raise ArgumentError, "Invalid instance state #{val.inspect}" unless STATES.include?(val)
      Log.info("Transitioning instance state from #{previous_val} to #{val}")
      @reboot = false if val != :booting
      @value = val
      @decommission_type = nil unless (@value == 'decommissioning' || @value == 'decommissioned')

      update_logger
      update_motd
      broadcast_wall unless (previous_val == val)
      record_state if RECORDED_STATES.include?(val)
      store_state
      @observers.each { |o| o.call(val) } if @observers

      val
    end

    # Set decommission type and set state to 'decommissioning'
    #
    # === Parameters
    # decommission_type(String):: One of RightScale::ShutdownRequest::LEVELS or nil
    #
    # === Return
    # result(String):: new decommission type
    #
    # === Raise
    # RightScale::ShutdownRequest::InvalidLevel:: Invalid decommission type
    def self.decommission_type=(decommission_type)
      unless RightScale::ShutdownRequest::LEVELS.include?(decommission_type)
        raise RightScale::ShutdownRequest::InvalidLevel.new("Unexpected decommission_type: #{decommission_type}")
      end
      @decommission_type = decommission_type
      self.value = 'decommissioning'
      @decommission_type
    end

    # Instance AWS id for EC2 instances
    #
    # === Return
    # resource_uid(String):: Instance AWS ID on EC2, equivalent on other cloud when available
    def self.resource_uid
      resource_uid = @resource_uid
    end

    # Is this the initial boot?
    #
    # === Return
    # res(Boolean):: Whether this is the instance first boot
    def self.initial_boot?
      res = @initial_boot
    end

    # Are we rebooting? (needed for RightScripts)
    #
    # === Return
    # res(Boolean):: Whether this instance was rebooted
    def self.reboot?
      res = @reboot
    end

    # Update the time this instance last received a message
    # thus demonstrating that it is still connected
    #
    # === Return
    # true:: Always return true
    def self.communicated
      now = Time.now.to_i
      if (now - @last_communication) > LAST_COMMUNICATION_STORAGE_INTERVAL
        @last_communication = now
        store_state
      end
    end

    # Ask core agent to shut ourselves down for soft termination
    # Do not specify the last recorded state since does not matter at this point
    # and no need to risk request failure
    # Add a timer to force shutdown if do not hear back from the cloud or the request hangs
    #
    # === Parameters
    # user_id(Integer):: ID of user that triggered soft-termination
    # skip_db_update(Boolean):: Whether to re-query instance state after call to Ec2 to terminate was made
    # kind(String):: 'terminate', 'stop' or 'reboot'
    #
    # === Return
    # true:: Always return true
    def self.shutdown(user_id, skip_db_update, kind)
      payload = {:agent_identity => @identity, :state => FINAL_STATE, :user_id => user_id, :skip_db_update => skip_db_update, :kind => kind}
      Sender.instance.send_request("/state_recorder/record", payload) do |r|
        res = OperationResult.from_results(r)
        case kind
        when 'reboot'
          RightScale::Platform.controller.reboot unless res.success?
        when 'terminate', 'stop'
          RightHttpClient.instance.close(:receive)
          Sender.instance.send_push("/registrar/remove", {:agent_identity => @identity, :created_at => Time.now.to_i})
          RightScale::Platform.controller.shutdown unless res.success?
        else
          Log.error("InstanceState.shutdown() kind was unexpected: #{kind}")
        end
      end
      case kind
      when 'reboot'
        EM_S.add_timer(FORCE_SHUTDOWN_DELAY) { RightScale::Platform.controller.reboot }
      when 'terminate', 'stop'
        EM_S.add_timer(FORCE_SHUTDOWN_DELAY) { RightScale::Platform.controller.shutdown }
      else
        Log.error("InstanceState.shutdown() kind was unexpected: #{kind}")
      end
    end

    # Set startup tags
    #
    # === Parameters
    # val(Array):: List of tags
    #
    # === Return
    # val(Array):: List of tags
    #
    # === Raise
    # RightScale::Exceptions::Application:: Cannot update in read-only mode
    def self.startup_tags=(val)
      raise RightScale::Exceptions::Application, "Not allowed to modify instance state in read-only mode" if @read_only
      if @startup_tags.nil? || @startup_tags != val
        @startup_tags = val
        # FIX: storing state on change to ensure the most current set of tags is available to
        #      cook (or other processes that load instance state) when it is launched.  Would
        #      be better to communicate state via other means.
        store_state
      end
      val
    end

    # Tags retrieved on startup
    #
    # === Return
    # tags(Array):: List of tags retrieved on startup
    def self.startup_tags
      @startup_tags
    end

    # Log level
    #
    # === Return
    # log_level(Const):: One of Logger::DEBUG...Logger::FATAL
    def self.log_level
      @log_level
    end

    # Callback given observer on all state transitions
    #
    # === Block
    # Given block should take one argument which will be the transitioned to state
    #
    # === Return
    # true:: Always return true
    def self.observe(&observer)
      @observers ||= []
      @observers << observer
      true
    end

    # Point logger to log file corresponding to current instance state
    #
    # === Return
    # true:: Always return true
    def self.update_logger
      previous_level = nil
      if @current_logger
        previous_level = @current_logger.level
        Log.remove_logger(@current_logger)
        @current_logger = nil
      end
      if file = log_file(@value)
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        @current_logger = ::Logger.new(file)
        @current_logger.level = previous_level if previous_level
        Log.add_logger(@current_logger)
      end
      true
    end

    # Record set of authorized login users
    #
    # === Parameters
    # login_users(Array[(LoginUser)]) set of authorized login users
    #
    # === Return
    # login_users(Array[(LoginUser)]) authorized login users
    #
    def self.login_policy=(login_policy)
      @login_policy = login_policy.dup
      File.open(LOGIN_POLICY_FILE, 'w') do |f|
        f.write(@login_policy.to_json)
      end
      login_policy
    end

    # Log file to be used for given instance state
    #
    # === Parameters
    # state(String):: Instance state, one of STATES
    #
    # === Return
    # log(String):: Log file path
    # nil:: Log file should not be changed
    def self.log_file(state)
      log_file = case state
        when 'booting'         then BOOT_LOG_FILE
        when 'decommissioning' then DECOMMISSION_LOG_FILE
      end
    end

    protected

    # Determine uptime of this system.
    #
    # === Return
    # uptime(Float):: Uptime of this system in seconds, or 0.0 if undetermined
    def self.uptime()
      return RightScale::Platform.shell.uptime
    end

    # Purely for informational purposes, attempt to update the Unix MOTD file
    # with a pretty banner indicating success or failure. This operation is
    # not critical and does not influence the functionality of the instance,
    # so this method fails silently.
    #
    # === Return
    # nil:: always return nil
    def self.update_motd()
      return unless (FeatureConfigManager.feature_enabled?('motd_update') && RightScale::Platform.linux?)

      if File.directory?('/etc/update-motd.d')
        #Ubuntu 10.04 and above use a dynamic MOTD update system. In this case we assume
        #by convention that motd.tail will be appended to the dynamically-generated
        #MOTD.
        motd = '/etc/motd.tail'
      else
        motd = '/etc/motd'
      end

      FileUtils.rm(motd) rescue nil

      etc = File.join(AgentConfig.parent_dir, 'etc')
      if SUCCESSFUL_STATES.include?(@value)
        FileUtils.cp(File.join(etc, 'motd-complete'), motd) rescue nil
      elsif FAILED_STATES.include?(@value)
        FileUtils.cp(File.join(etc, 'motd-failed'), motd) rescue nil
      else
        FileUtils.cp(File.join(etc, 'motd'), motd) rescue nil
      end

      return nil
    end

    # Purely for informational purposes, attempt to wall-broadcast a RightLink
    # state transition. This should get the attention of anyone who's logged in.
    #
    # === Return
    # nil:: always return nil
    def self.broadcast_wall
      # linux only, don't broadcast during rspec runs because it is very annoying.
      return if !RightScale::Platform.linux? || defined?(::Spec) || defined?(::RSpec)

      if SUCCESSFUL_STATES.include?(@value)
        system('echo "RightScale installation complete. Details can be found in system logs." | wall > /dev/null 2>&1') rescue nil
      elsif FAILED_STATES.include?(@value)
        system('echo "RightScale installation failed. Please review system logs." | wall > /dev/null 2>&1') rescue nil
      end
      nil
    end

    private

    # Persist state to local disk storage
    #
    # === Return
    # true:: Always return true
    def self.store_state
      state_to_store = {'value'                      => @value,
                        'identity'                   => @identity,
                        'uptime'                     => uptime,
                        'reboot'                     => @reboot,
                        'startup_tags'               => @startup_tags,
                        'log_level'                  => @log_level,
                        'record_retries'             => @record_retries,
                        'last_recorded_value'        => @last_recorded_value,
                        'last_communication'         => @last_communication,
                        'last_observed_resource_uid' => @resource_uid}

      # Only include deommission_type when decommissioning
      state_to_store['decommission_type'] = @decommission_type if (@value == 'decommissioning' || @value == 'decommissioned')

      RightScale::JsonUtilities::write_json(STATE_FILE, state_to_store)
      true
    end

    # Record state transition
    # Cancel any active attempts to record state before doing this one
    # Retry up to MAX_RECORD_STATE_RETRIES times if an error is returned
    # If state has changed during a failed attempt, reset retry counter
    #
    # === Return
    # true:: Always return true
    def self.record_state
      # Cancel any running request
      if @record_request
        @record_request.cancel("re-request")
        if @record_timer
          @record_timer.cancel
          @record_timer = nil
        end
      end

      # Create new request
      new_value = @value
      payload = {:agent_identity => @identity, :state => new_value, :from_state => @last_recorded_value}
      @record_request = RightScale::RetryableRequest.new("/state_recorder/record", payload)

      # Handle success result
      @record_request.callback do
        @record_retries = 0
        @record_request = nil
        @last_recorded_value = new_value

        # Store any change in local state, recorded state, or retry count
        store_state
      end

      # Handle request failure
      @record_request.errback do |error|
        if /currently recorded state \((?<recorded_state>[^\)]*)\)/ =~ error
          # State transitioning from does not match recorded state, so update last recorded value
          @last_recorded_value = recorded_state
        end
        if error != "re-request" && @value != @last_recorded_value
          attempts = " after #{@record_retries + 1} attempts" if @record_retries >= MAX_RECORD_STATE_RETRIES
          Log.error("Failed to record state '#{new_value}'#{attempts} (#{error})") unless @value == FINAL_STATE
          @record_retries = 0 if @value != new_value
          if RECORDED_STATES.include?(@value) && @record_retries < MAX_RECORD_STATE_RETRIES
            Log.info("Will retry recording state in #{RETRY_RECORD_STATE_DELAY} seconds")
            @record_timer = EM::Timer.new(RETRY_RECORD_STATE_DELAY) do
              if @value != @last_recorded_value
                @record_retries += 1
                @record_request = nil
                @record_timer = nil
                record_state
              end
            end
          else
            # Give up since out of retries or state has changed to a non-recorded value
            @record_retries = 0
            @record_request = nil
          end

          # Store any change in local state, recorded state, or retry count
          store_state
        end
      end

      # Run request to record state with retry until succeeds or fails with error result
      @record_request.run
    end

    #
    # retrieve the resource uid from the metadata
    #
    # === Return
    # resource_uid(String|nil):: the resource uid or nil
    def self.current_resource_uid
      resource_uid = nil
      begin
        meta_data_file = ::File.join(AgentConfig.cloud_state_dir, 'meta-data-cache.rb')
        # metadata does not exist on all clouds, hence the conditional
        load(meta_data_file) if File.file?(meta_data_file)
        resource_uid = ENV['EC2_INSTANCE_ID']
      rescue Exception => e
        Log.warning("Failed to load metadata", e)
      end
      resource_uid
    end
  end

end
