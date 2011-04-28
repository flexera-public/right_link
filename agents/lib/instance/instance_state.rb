#
# Copyright (c) 2009 RightScale Inc
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

module RightScale

  # Manages instance state
  class InstanceState

    # States that are recorded in a standard fashion and audited when transitioned to
    RECORDED_STATES   = %w{ booting operational stranded decommissioning }

    # States that cause the system MOTD/banner to indicate that everything is OK
    SUCCESSFUL_STATES = %w{ operational }

    # States that cause the system MOTD/banner to indicate that something is wrong
    FAILED_STATES     = %w{ stranded }

    # Initial state prior to booting
    INITIAL_STATE     = 'pending'

    # Final state when shutting down that is recorded in a non-standard fashion
    FINAL_STATE       = 'decommissioned'

    # Valid internal states
    STATES            = RECORDED_STATES + FINAL_STATE.to_a

    # Path to JSON file where current instance state is serialized
    STATE_DIR         = RightScale::RightLinkConfig[:agent_state_dir]
    STATE_FILE        = File.join(STATE_DIR, 'state.js')

    # Path to JSON file where authorized login users are defined
    LOGIN_POLICY_FILE = File.join(STATE_DIR, 'login_policy.js')

    # Path to boot log
    BOOT_LOG_FILE     = File.join(RightLinkConfig[:platform].filesystem.log_dir, 'install')

    # Path to decommission log
    DECOMMISSION_LOG_FILE = File.join(RightLinkConfig[:platform].filesystem.log_dir, 'decommission')

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
      @@value
    end

    # (String) One of STATES
    def self.last_recorded_value
      @@last_recorded_value
    end

    # (String) Instance agent identity
    def self.identity
      @@identity
    end

    # (LoginPolicy) The most recently enacted login policy
    def self.login_policy
      @@login_policy
    end

    # Queries most recent state of planned volume mappings.
    #
    # === Return
    # result(Array):: persisted mappings or empty
    def self.planned_volume_state
      @@planned_volume_state ||= PlannedVolumeState.new
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
      @@identity = identity
      @@read_only = read_only
      @@startup_tags = []
      @@log_level = Logger::INFO
      @@initial_boot = false
      @@reboot = false
      @@resource_uid = nil
      @@last_recorded_value = nil
      @@record_retries = 0
      @@last_communication = 0
      @@planned_volume_state = nil
      @@shutdown_request = nil

      MapperProxy.instance.message_received { message_received } unless @@read_only

      dir = File.dirname(STATE_FILE)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
      if File.file?(STATE_FILE)
        state = RightScale::JsonUtilities::read_json(STATE_FILE)
        RightLinkLog.debug("Initializing instance #{identity} with #{state.inspect}")

        @@resource_uid = current_resource_uid

        # Initial state reconciliation: use recorded state and boot timestamp to determine how we last stopped.
        # There are four basic scenarios to worry about:
        #  1) first run          -- Agent is starting up for the first time after a fresh install
        #  2) reboot/restart     -- Agent already ran; agent ID not changed; reboot detected: transition back to booting
        #  3) bundled boot       -- Agent already ran; agent ID changed: transition back to booting
        #  4) decommission/crash -- Agent exited anyway; ID not changed; no reboot; keep old state entirely
        #  5) ec2 restart        -- Agent already ran; agent ID changed; instance ID is the same; transition back to booting
        if state['identity'] && state['identity'] != identity
          @@last_recorded_value = state['last_recorded_value']
          self.value = 'booting'
          # if the current resource_uid is the same as the last
          # observed resource_uid, then this is a restart,
          # otherwise this is a bundle
          old_resource_uid = state["last_observed_resource_uid"]
          if @@resource_uid && @@resource_uid == old_resource_uid
            # CASE 5 -- identity has changed; ec2 restart
            RightLinkLog.debug("Restart detected; transitioning state to booting")
            @@reboot = true
          else
            # CASE 3 -- identity has changed; bundled boot
            RightLinkLog.debug("Bundle detected; transitioning state to booting")
          end
        elsif state['reboot']
          # CASE 2 -- rebooting flagged by rightboot script in linux or by shutdown notification in windows
          RightLinkLog.debug("Reboot detected; transitioning state to booting")
          @@last_recorded_value = state['last_recorded_value']
          self.value = 'booting'
          @@reboot = true
        else
          # CASE 4 -- restart without reboot; continue with retries if recorded state does not match
          @@value = state['value']
          @@startup_tags = state['startup_tags']
          @@log_level = state['log_level']
          @@last_recorded_value = state['last_recorded_value']
          @@record_retries = state['record_retries']
          if @@value != @@last_recorded_value && RECORDED_STATES.include?(@@value) &&
             @@record_retries < MAX_RECORD_STATE_RETRIES && !@@read_only
            record_state
          else
            @@record_retries = 0
          end
          update_logger
        end
      else
        # CASE 1 -- state file does not exist; initial boot, create state file
        RightLinkLog.debug("Initializing instance #{identity} with booting")
        @@last_recorded_value = INITIAL_STATE
        self.value = 'booting'
        @@initial_boot = true
      end

      if File.file?(LOGIN_POLICY_FILE)
        @@login_policy = RightScale::JsonUtilities::read_json(LOGIN_POLICY_FILE) rescue nil #corrupt file here is not important enough to fail
      else
        @@login_policy = nil
      end
      RightLinkLog.debug("Existing login users: #{@@login_policy.users.length} recorded") if @@login_policy

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
    # RightScale::Exceptions::Argument:: Invalid new value
    def self.value=(val)
      raise RightScale::Exceptions::Application, "Not allowed to modify instance state in read-only mode" if @@read_only
      raise RightScale::Exceptions::Argument, "Invalid instance state #{val.inspect}" unless STATES.include?(val)
      RightLinkLog.info("Transitioning state from #{@@value rescue INITIAL_STATE} to #{val}")
      @@reboot = false if val != :booting
      @@value = val
      update_logger
      update_motd
      record_state if RECORDED_STATES.include?(val)
      store_state
      @observers.each { |o| o.call(val) } if @observers
      val
    end

    # Instance AWS id for EC2 instances
    #
    # === Return
    # resource_uid(String):: Instance AWS ID on EC2, equivalent on other cloud when available
    def self.resource_uid
      resource_uid = @@resource_uid
    end

    # Is this the initial boot?
    #
    # === Return
    # res(Boolean):: Whether this is the instance first boot
    def self.initial_boot?
      res = @@initial_boot
    end

    # Are we rebooting? (needed for RightScripts)
    #
    # === Return
    # res(Boolean):: Whether this instance was rebooted
    def self.reboot?
      res = @@reboot
    end

    # Update the time this instance last received a message
    # thus demonstrating that it is still connected
    #
    # === Return
    # true:: Always return true
    def self.message_received
      now = Time.now.to_i
      if (now - @@last_communication) > LAST_COMMUNICATION_STORAGE_INTERVAL
        @@last_communication = now
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
      payload = {:agent_identity => @@identity, :state => FINAL_STATE, :user_id => user_id, :skip_db_update => skip_db_update, :kind => kind}
      MapperProxy.instance.send_retryable_request("/state_recorder/record", payload, nil, :offline_queueing => true) do |r|
        res = OperationResult.from_results(r)
        case kind
        when 'reboot'
          Platform.controller.reboot unless res.success?
        when 'terminate', 'stop'
          MapperProxy.instance.send_push("/registrar/remove", {:agent_identity => @@identity, :created_at => Time.now.to_i},
                                         nil, :offline_queueing => true)
          Platform.controller.shutdown unless res.success?
        else
          RightLinkLog.error("InstanceState.shutdown() kind was unexpected: #{kind}")
        end
      end
      case kind
      when 'reboot'
        EM.add_timer(FORCE_SHUTDOWN_DELAY) { Platform.controller.reboot }
      when 'terminate', 'stop'
        EM.add_timer(FORCE_SHUTDOWN_DELAY) { Platform.controller.shutdown }
      else
        RightLinkLog.error("InstanceState.shutdown() kind was unexpected: #{kind}")
      end
    end

    # Current requested shutdown state, if any.
    def self.shutdown_request
      @@shutdown_request ||= ::RightScale::ShutdownManagement::ShutdownRequest.new
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
      raise RightScale::Exceptions::Application, "Not allowed to modify instance state in read-only mode" if @@read_only
      if @@startup_tags.nil? || @@startup_tags != val
        @@startup_tags = val
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
      @@startup_tags
    end

    # Set log level
    #
    # === Parameters
    # val(Const):: One of Logger::DEBUG...Logger::FATAL
    #
    # === Return
    # val(Const):: One of Logger::DEBUG...Logger::FATAL
    def self.log_level=(val)
      @@log_level = val
    end

    # Log level
    #
    # === Return
    # log_level(Const):: One of Logger::DEBUG...Logger::FATAL
    def self.log_level
      @@log_level
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
        RightLinkLog.remove_logger(@current_logger)
        @current_logger = nil
      end
      if file = log_file(@@value)
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        @current_logger = ::Logger.new(file)
        @current_logger.level = previous_level if previous_level
        RightLinkLog.add_logger(@current_logger)
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
      @@login_policy = login_policy.dup
      File.open(LOGIN_POLICY_FILE, 'w') do |f|
        f.write(@@login_policy.to_json)
      end
      login_policy
    end

    protected

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

    # Determine uptime of this system.
    #
    # === Return
    # uptime(Float):: Uptime of this system in seconds, or 0.0 if undetermined
    def self.uptime()
      return RightLinkConfig[:platform].shell.uptime
    end

    # Purely for informational purposes, attempt to update the Unix MOTD file
    # with a pretty banner indicating success or failure. This operation is
    # not critical and does not influence the functionality of the instance,
    # so this method fails silently.
    #
    # === Return
    # nil:: always return nil
    def self.update_motd()
      return unless RightLinkConfig.platform.linux?

      if File.directory?('/etc/update-motd.d')
        #Ubuntu 10.04 and above use a dynamic MOTD update system. In this case we assume
        #by convention that motd.tail will be appended to the dynamically-generated
        #MOTD.
        motd = '/etc/motd.tail'
      else
        motd = '/etc/motd'
      end

      FileUtils.rm(motd) rescue nil

      etc = File.join(RightLinkConfig[:rs_root_path], 'etc')
      if SUCCESSFUL_STATES.include?(@@value)
        FileUtils.cp(File.join(etc, 'motd-complete'), motd) rescue nil
        system('echo "RightScale installation complete. Details can be found in /var/log/messages" | wall') rescue nil
      elsif FAILED_STATES.include?(@@value)
        FileUtils.cp(File.join(etc, 'motd-failed'), motd) rescue nil
        system('echo "RightScale installation failed. Please review /var/log/messages" | wall') rescue nil
      else
        FileUtils.cp(File.join(etc, 'motd'), motd) rescue nil
      end

      return nil
    end

    private

    # Persist state to local disk storage
    #
    # === Return
    # true:: Always return true
    def self.store_state
      RightScale::JsonUtilities::write_json(STATE_FILE, {'value'                      => @@value,
                                                         'identity'                   => @@identity,
                                                         'uptime'                     => uptime,
                                                         'reboot'                     => @@reboot,
                                                         'startup_tags'               => @@startup_tags,
                                                         'log_level'                  => @@log_level,
                                                         'record_retries'             => @@record_retries,
                                                         'last_recorded_value'        => @@last_recorded_value,
                                                         'last_communication'         => @@last_communication,
                                                         'last_observed_resource_uid' => @@resource_uid})
      true
    end

    # Record state transition
    # Retry up to MAX_RECORD_STATE_RETRIES times if an error is returned
    # If state has changed during a failed attempt, reset retry counter
    #
    # === Return
    # true:: Always return true
    def self.record_state
      new_value = @@value
      payload = {:agent_identity => @@identity, :state => new_value, :from_state => @@last_recorded_value}
      MapperProxy.instance.send_retryable_request("/state_recorder/record", payload, nil, :offline_queueing => true) do |r|
        res = OperationResult.from_results(r)
        if res.success?
          @@last_recorded_value = new_value
          @@record_retries = 0
        else
          error = if res.content.is_a?(Hash) && res.content['recorded_state']
            # State transitioning from does not match recorded state, so update last recorded value
            @@last_recorded_value = res.content['recorded_state']
            res.content['message']
          else
            res.content
          end
          if @@value != @@last_recorded_value
            attempts = " after #{@@record_retries + 1} attempts" if @@record_retries >= MAX_RECORD_STATE_RETRIES
            RightLinkLog.error("Failed to record state '#{new_value}'#{attempts}: #{error}") unless @@value == FINAL_STATE
            @@record_retries = 0 if @@value != new_value
            if RECORDED_STATES.include?(@@value) && @@record_retries < MAX_RECORD_STATE_RETRIES
              RightLinkLog.info("Will retry recording state in #{RETRY_RECORD_STATE_DELAY} seconds")
              EM.add_timer(RETRY_RECORD_STATE_DELAY) do
                if @@value != @@last_recorded_value
                  @@record_retries += 1
                  record_state
                end
              end
            else
              # Giving up since out of retries or state has changed to a non-recorded value
              @@record_retries = 0
            end
          end
        end
        # Store any change in local state, recorded state, or retry count
        store_state
      end
      true
    end

    #
    # retrieve the resource uid from the metadata
    #
    # === Return
    # resource_uid(String|nil):: the resource uid or nil
    def self.current_resource_uid
      resource_uid = nil
      begin
        meta_data_file = ::File.join(RightScale::RightLinkConfig[:cloud_state_dir], 'meta-data-cache.rb')
        # metadata does not exist on all clouds, hence the conditional
        load(meta_data_file) if File.file?(meta_data_file)
        resource_uid = ENV['EC2_INSTANCE_ID']
      rescue Exception => e
        RightLinkLog.warn("Failed to load metadata: #{e.message}, #{e.backtrace[0]}")
      end
      resource_uid
    end
  end

end
