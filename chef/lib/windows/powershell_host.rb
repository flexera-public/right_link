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
    
    # Is the Powershell process running?
    attr_reader :active
    
    # Start the Powershell process synchronously
    # Set the instance variable :active to true once Powershell was
    # successfully started
    def initialize(options = {})
      @execute_status = nil
      @command_queue  = Queue.new
      @node           = options[:chef_node] || nil

      @pipe_server      = RightScale::Windows::PowershellPipeServer.new(:queue => @command_queue, :logger =>  Chef::Log.logger)
      @chef_node_server = RightScale::Windows::ChefNodeServer.new(:node => @node, :logger => Chef::Log.logger)
                
      client_command = format_command(::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', 'lib', 'windows', 'scripts', 'run_loop.ps1')))
      execute(client_command, nil)
      
      @active = true
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
      Chef::Log.logger.info("Powershell Host - Run #{script_path}")
      @command_queue.push(". \"#{script_path}\"")  
    end
    
    # Terminate associated Powershell process
    # :run cannot be called after :terminate
    # This method is idempotent
    #
    # === Return
    # true:: Always return true
    def terminate
      Chef::Log.logger.info("Powershell Host - Terminiated")
      @command_queue.push("exit")
    end
    
    protected
    
    # Resolves a loadable location for the ChefNodeCmdlet.dll
    def self.locate_chef_node_cmdlet
      cmdlet_path = ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', 'lib', 'windows', 'bin', 'ChefNodeCmdlet.dll'))

      # handle case of running spec tests from a network drive by copying .dll
      # to the system drive. Powershell silently fails to load modules from
      # network drives, so the .dll needs to be copied locally ro tun. the
      # .dll location will be the HOMEDRIVE in release use cases or on the
      # build/test machine so this is only meant for VM images running tests
      # from a shared drive.
      homedrive = ENV['HOMEDRIVE']
      if homedrive && homedrive.upcase != cmdlet_path[0,2].upcase
        temp_dir = ::File.normalize_path(::File.join(RightScale::RightLinkConfig[:platform].filesystem.temp_dir, 'powershell_host-82D5D281-5E7C-423A-88C2-69E9B7D3F37E'))
        FileUtils.rm_rf(temp_dir) if ::File.directory?(temp_dir)
        FileUtils.mkdir_p(temp_dir)
        FileUtils.cp_r(::File.join(::File.dirname(cmdlet_path), '.'), temp_dir)
        cmdlet_path = ::File.join(temp_dir, ::File.basename(cmdlet_path))
      end

      return RightScale::RightLinkConfig[:platform].filesystem.long_path_to_short_path(cmdlet_path).gsub("/", "\\")
    end

    CHEF_NODE_CMDLET_DLL_PATH = locate_chef_node_cmdlet

    # Formats a command to run the given powershell script.
    #
    # === Parameters
    # script_file_path(String):: powershell script file path
    #
    # == Returns
    # command(String):: command to execute
    def format_command(script_file_path)
      platform = RightScale::RightLinkConfig[:platform]
      shell    = platform.shell

      # import ChefNodeCmdlet.dll to allow powershell scripts to call get-ChefNode, etc.
      lines_before_script = ["import-module #{CHEF_NODE_CMDLET_DLL_PATH}"]

      return shell.format_powershell_command4(RightScale::Platform::Windows::Shell::POWERSHELL_V1x0_EXECUTABLE_PATH, lines_before_script, nil, script_file_path)
    end
    
    
    def execute(command, env=nil)
        @pipe_server.start
        @chef_node_server.start
        
        Chef::Log.debug("Executing \"#{command}\"")
        
        RightScale.popen3(:command        => command,
                          :environment    => env,
                          :target         => self,
                          :stdout_handler => :on_read_output,
                          :stderr_handler => :on_read_output,
                          :exit_handler   => :on_exit,
                          :temp_dir       => RightScale::InstanceConfiguration::CACHE_PATH)

        return true
      end

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
        @pipe_server.stop
        @chef_node_server.stop
        
        @active = false
      end
  end
end