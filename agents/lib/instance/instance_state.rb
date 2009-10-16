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

module RightScale

  # Manages instance state 
  class InstanceState

    # States that will be audited when transitioned to
    RECORDED_STATES   = %w{ booting operational stranded decommissioning }

    # States that cause the system MOTD/banner to indicate that everything is OK
    SUCCESSFUL_STATES = %w{ operational }

    # States that cause the system MOTD/banner to indicate that something is wrong
    FAILED_STATES     = %w{ stranded }

    # Recorded states and additional states local to instance agent
    STATES            = RECORDED_STATES + %w{ decommissioned }

    STATE_DIR       = RightScale::RightLinkConfig[:agent_state_dir]

    # Path to JSON file where current instance state is serialized
    STATE_FILE      = File.join(STATE_DIR, 'state.js')

    # Path to JSON file where past scripts are serialized
    SCRIPTS_FILE    = File.join(STATE_DIR, 'past_scripts.js')

    # Path to boot log
    BOOT_LOG_FILE = '/var/log/install'

    # Path to operation log
    OPERATION_LOG_FILE = '/var/log/right_link'

    # Path to decommission log
    DECOMMISSION_LOG_FILE = '/var/log/decomm'

    # <String> One of STATES
    def self.value
      @@value
    end

    # <String> Instance agent identity
    def self.identity
      @@identity
    end

    # <Array[<String>]> Scripts that have already executed
    def self.past_scripts
      @@past_scripts
    end
  
    # Set instance id with given id
    # Load persisted state if any, compare instance ids and force boot if instance ID
    # is different OR if system uptime is less than persisted uptime.
    #
    # === Parameters
    # identity<String>:: Instance identity
    # booting<Boolean>:: Force instance boot regardless of instance ID or uptime
    #
    # === Return
    # true:: Always return true
    def self.init(identity, booting=false)
      @@identity = identity
      dir = File.dirname(STATE_FILE)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)

      if File.file?(STATE_FILE)
        state = JSON.load(File.new(STATE_FILE))
        RightLinkLog.debug("Initializing instance #{identity} with #{state.inspect}")
        if booting || (state['identity'] != identity) || !state['uptime'] || (uptime < state['uptime'].to_f)
          # If identity or uptime has changed, then we are booting
          RightLinkLog.debug("Reboot detected; transitioning state to booting")
          self.value = 'booting'

          # If our identity has changed, then we are a bundled instance and we
          # need to patch our identity and reset our past scripts.
          if state['identity'] != identity
            RightLinkLog.debug("Bundled boot detected; resetting past scripts")
            @@past_scripts = []
            File.open(SCRIPTS_FILE, 'w') do |f|
              f.write(@@past_scripts.to_json)
            end
          end
        else
          # Agent restarted by itself, keep the old state
          @@value = state['value']
          update_logger
        end
      else
        # Initial boot, create state file
        RightLinkLog.debug("Initializing instance #{identity} with booting")
        self.value = 'booting'
      end

      if File.file?(SCRIPTS_FILE)
        @@past_scripts = JSON.load(File.new(SCRIPTS_FILE))
      else
        @@past_scripts = []
      end

      RightLinkLog.debug("Past scripts: #{@@past_scripts.inspect}")
      true
    end

    # Set instance state
    #
    # === Parameters
    # val<String> One of STATES
    #
    # === Return
    # val<String> new state
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Invalid new value
    def self.value=(val)
      raise RightScale::Exceptions::Argument, "Invalid instance state '#{val}'" unless STATES.include?(val)
      RightLinkLog.debug("Transitioning state from #{@@value rescue 'nil'} to #{val}")
      @@value = val
      update_logger
      update_motd
      if RECORDED_STATES.include?(val)
        options = { :agent_identity => identity, :state => val }
        Nanite::MapperProxy.instance.request('/state_recorder/record', options) do |r|
          res = RightScale::OperationResult.from_results(r)
          RightLinkLog.warn("Failed to record state: #{res.content}") unless res.success?
        end
      end
      File.open(STATE_FILE, 'w') do |f|
        f.write({ 'value' => val, 'identity' => @@identity, 'uptime' => uptime.to_s }.to_json)
      end
      val
    end

    # Point logger to log file corresponding to current instance state
    #
    # === Return
    # true:: Always return true
    def self.update_logger
      if file = log_file(@@value)
        previous_level = nil
        if @current_logger
          previous_level = @current_logger.level
          RightLinkLog.remove_logger(@current_logger)
        end
        @current_logger = ::Logger.new(File.open(file, 'w'))
        @current_logger.level = previous_level if previous_level
        RightLinkLog.add_logger(@current_logger)
      end
      true
    end

    # Record script execution in scripts file
    #
    # === Parameters
    # nickname<String>:: Nickname of RightScript which successfully executed
    #
    # === Return
    # true:: If script was added to past scripts collection
    # false:: If script was already in past scripts collection
    def self.record_script_execution(nickname)
      new_script = !@@past_scripts.include?(nickname)
      if new_script
        @@past_scripts << nickname
        File.open(SCRIPTS_FILE, 'w') do |f|
          f.write(@@past_scripts.to_json)
        end
      end
      new_script
    end

    protected

    # Log file to be used for given instance state
    #
    # === Parameters
    # state<String>:: Instance state, one of STATES
    #
    # === Return
    # log<String>:: Log file path
    # nil:: Log file should not be changed
    def self.log_file(state)
      log_file = case state
        when 'booting'         then BOOT_LOG_FILE
        when 'operational'     then OPERATION_LOG_FILE
        when 'decommissioning' then DECOMMISSION_LOG_FILE
      end
    end

    # Determine uptime of this system using the proc filesystem
    #
    # === Return
    # uptime<Float>:: Uptime of this system in seconds, or 0.0 if undetermined 
    def self.uptime()
      return File.read('/proc/uptime').split(/\s+/)[0].to_f rescue 0.0
    end

    # Purely for informational purposes, attempt to update the Unix MOTD file
    # with a pretty banner indicating success or failure. This operation is
    # not critical and does not influence the functionality of the instance,
    # so this method fails silently.
    #
    # === Return
    # nil:: always return nil
    def self.update_motd()
      return unless RightScale::RightLinkConfig.platform.linux?
      
      FileUtils.rm('/etc/motd') rescue nil

      etc = File.join(RightScale::RightLinkConfig[:rs_root_path], 'etc')
      if SUCCESSFUL_STATES.include?(@@value)
        FileUtils.cp(File.join(etc, 'motd-complete'), '/etc/motd') rescue nil
        system('echo "RightScale installation complete. Details can be found in /var/log/messages" | wall') rescue nil
      elsif FAILED_STATES.include?(@@value)
        FileUtils.cp(File.join(etc, 'motd-failed'), '/etc/motd') rescue nil
        system('echo "RightScale installation failed. Please review /var/log/messages" | wall') rescue nil
      else
        FileUtils.cp(File.join(etc, 'motd'), '/etc/motd') rescue nil
      end

      return nil
    end

  end

end