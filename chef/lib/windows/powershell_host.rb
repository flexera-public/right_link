#
# Copyright (c) 2010 RightScale Inc
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

module RightScale
  
  # This class is responsible for managing a Powershell process instance
  # It allows running Powershell scripts in the associated instance and will
  # log the script output.
  class PowershellHost
    
    # Start the Powershell process synchronously
    # Set the instance variable :active to true once Powershell was
    # successfully started
    #
    # === Parameters
    # options[:node]:: Chef @node object
    # options[:provider_name]:: Associated Chef powershell provider name
    def initialize(options = {})
      RightLinkLog.debug(format_log_message("Initializing"))
      @node           = options[:node]
      @pipe_name      = "#{options[:provider_name]}_#{Time.now.strftime("%Y-%m-%d-%H%M%S")}"

      @response_mutex = Mutex.new
      @response_event = ConditionVariable.new

      RightLinkLog.debug(format_log_message("Starting pipe server"))
      @pipe_server = RightScale::Windows::PowershellPipeServer.new(:pipe_name => @pipe_name) do |kind, _|
        case kind
          when :is_ready then query
          when :respond  then respond
        end
      end

      unless @pipe_server.start
        @pipe_server = nil
        return
      end

      RightLinkLog.debug(format_log_message("Starting chef node server"))
      RightScale::Windows::ChefNodeServer.instance.start(:node => @node)

      RightLinkLog.debug(format_log_message("Starting host"))
      start_powershell_process
      
      RightLinkLog.debug(format_log_message("Initialized"))
    end

    def format_log_message(message)
      "[PowershellHost #{@pipe_name}] - #{message}"
    end


    # Is the Powershell process running?
    #
    # === Return
    # true:: If the associated Powershell process is running
    # false:: Otherwise
    def active
      !!@pipe_server
    end

    # Run Powershell script in associated Powershell process
    # Log stdout and stderr to Chef logger
    #
    # === Argument
    # script_path(String):: Full path to Powershell script to be run
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # RightScale::Exceptions:ApplicationError:: If Powershell process is not running (i.e. :active is false)
    def run(script_path)
      RightLinkLog.debug(format_log_message("\n\n\n++++++++++++++++++++\nRunning #{script_path}"))
      run_command("&\"#{script_path}\"")
      RightLinkLog.debug(format_log_message("Finished #{script_path}\n++++++++++++++++++++\n\n\n"))
    end

    # Terminate associated Powershell process
    # :run cannot be called after :terminate
    # This method is idempotent
    #
    # === Return
    # true:: Always return true
    def terminate
      RightLinkLog.debug(format_log_message("Terminate requested"))
      run_command("break")
    end

    protected

    # Query whether there is a command to execute
    # Also signal waiting Chef thread if a command executed
    #
    # === Return
    # true:: If there is a command to execute
    # false:: Otherwise
    def query
      @response_mutex.synchronize do
        if @sent_command
          RightLinkLog.debug(format_log_message("Completed last command"))
          @sent_command = false
          @response_event.signal
        end
      end
      RightLinkLog.debug(format_log_message("Command Ready??? #{!!@pending_command}"))
      return !!@pending_command
    end

    # Respond to pipe server request
    # Send pending command
    #
    # === Return
    # res(String):: Command to execute
    def respond
      @sent_command = true
      res = @pending_command
      @pending_command = nil
      RightLinkLog.debug(format_log_message("Responding with pending command #{res}"))
      return res
    end

    # Start the associated powershell process
    #
    # === Return
    # true:: Always return true
    def start_powershell_process
      platform = RightScale::RightLinkConfig[:platform]
      shell    = platform.shell

      # Import ChefNodeCmdlet.dll to allow powershell scripts to call get-ChefNode, etc.
      # Also pass in name of pipe that client needs to connect to
      lines_before_script = ["import-module #{CHEF_NODE_CMDLET_DLL_PATH}", "$pipeName='#{@pipe_name}'"]

      command = shell.format_powershell_command4(RightScale::Platform::Windows::Shell::POWERSHELL_V1x0_EXECUTABLE_PATH, lines_before_script, nil, RUN_LOOP_SCRIPT_PATH)

      RightLinkLog.debug(format_log_message("Starting powershell process for host #{command}"))

      RightScale.popen3(:command        => command,
                        :environment    => nil,
                        :target         => self,
                        :stdout_handler => :on_read_output,
                        :stderr_handler => :on_read_output,
                        :exit_handler   => :on_exit,
                        :temp_dir       => RightScale::InstanceConfiguration::CACHE_PATH)

      return true
    end

    # executes a powershell command and waits until the command has completed
    #
    # === Argument
    # command(String):: a powershell command
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # RightScale::Exceptions::Application:: If Powershell process is not running (i.e. :active is false)
    def run_command(command) 
      raise RightScale::Exceptions::Application, "Powershell host not active, cannot run: #{command}" unless active
      @response_mutex.synchronize do
        @pending_command = command
        @response_event.wait(@response_mutex)
        @pending_command = nil
        @sent_command = false
      end

      true
    end

    # Resolves a loadable location for the ChefNodeCmdlet.dll
    def self.locate_local_windows_modules
      windows_path = ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', 'lib', 'windows'))

      # handle case of running spec tests from a network drive by copying .dll
      # to the system drive. Powershell silently fails to load modules from
      # network drives, so the .dll needs to be copied locally ro tun. the
      # .dll location will be the HOMEDRIVE in release use cases or on the
      # build/test machine so this is only meant for VM images running tests
      # from a shared drive.
      homedrive = ENV['HOMEDRIVE']
      if homedrive && homedrive.upcase != windows_path[0,2].upcase
        temp_dir = ::File.normalize_path(::File.join(RightScale::RightLinkConfig[:platform].filesystem.temp_dir, 'powershell_host-82D5D281-5E7C-423A-88C2-69E9B7D3F37E'))
        FileUtils.rm_rf(temp_dir) if ::File.directory?(temp_dir)
        FileUtils.mkdir_p(temp_dir)
        FileUtils.cp_r(::File.join(windows_path, 'bin', '.'), ::File.join(temp_dir, 'bin'))
        FileUtils.cp_r(::File.join(windows_path, 'scripts', '.'), ::File.join(temp_dir, 'scripts'))
        windows_path = temp_dir
      end

      return windows_path
    end

    LOCAL_WINDOWS_PATH = locate_local_windows_modules
    CHEF_NODE_CMDLET_DLL_PATH = File.normalize_path(File.join(LOCAL_WINDOWS_PATH, 'bin', 'ChefNodeCmdlet.dll')).gsub("/", "\\")
    RUN_LOOP_SCRIPT_PATH = File.normalize_path(File.join(LOCAL_WINDOWS_PATH, 'scripts', 'run_loop.ps1')).gsub("/", "\\")

    # Data available in STDOUT pipe event
    # Audit raw output
    #
    # === Parameters
    # data(String):: STDOUT data
    #
    # === Return
    # true:: Always return true
    def on_read_output(data)
      ::Chef::Log.info(data)
    end

    # Process exited event
    # Record duration and process exist status and signal Chef thread so it can resume
    #
    # === Parameters
    # status(Process::Status):: Process exit status
    #
    # === Return
    # true:: Always return true
    def on_exit(status)
      RightLinkLog.debug(format_log_message("Stopping pipe server"))
      @pipe_server.stop
      @pipe_server = nil

      RightLinkLog.debug(format_log_message("Stopping chef node server"))
      RightScale::Windows::ChefNodeServer.instance.stop

      RightLinkLog.debug(format_log_message("Terminated"))
      @response_event.signal
    end
  end
end