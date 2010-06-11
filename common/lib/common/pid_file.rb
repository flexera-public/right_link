#
# Copyright (c) 2009-2010 RightScale Inc
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

  # Encapsulates an agent pid file
  # A pid file contains three components:
  #   - the PID of the process running the agent
  #   - the port number that should be used to talk to the agent via the
  #     command protocol
  #   - the cookie used to authenticate a client talking to the agent via
  #     the command protocol
  class PidFile

    # Initialize pid file location from given options and agent identity
    def initialize(identity, options)
      @pid_dir = File.normalize_path(options[:pid_dir] || options[:root] || Dir.pwd)
      @pid_file = File.join(@pid_dir, "nanite.#{identity}.pid")
    end

    # Check whether pid file can be created
    # Delete any existing pid file if process is not running anymore
    #
    # === Return
    # true:: Always return true
    def check
      if pid = read_pid[:pid]
        if process_running? pid
          raise "#{@pid_file} already exists (pid: #{pid})"
        else
          RightLinkLog.info "removing stale pid file: #{@pid_file}"
          remove
        end
      end
      true
    end
    
    # Write pid to pid file
    #
    # === Return
    # true:: Always return true
    def write
      FileUtils.mkdir_p(@pid_dir)
      open(@pid_file,'w') { |f| f.write(YAML.dump({ :pid => Process.pid })) }
      File.chmod(0644, @pid_file)
      true
    end
    
    # Update associated command protocol port
    #
    # === Parameters
    # options[:listen_port](Integer):: Command protocol port to be used for this agent
    # options[:cookie](String):: Cookie to be used together with command protocol
    #
    # === Return
    # true:: Always return true
    def set_command_options(options)
      content = read_pid
      content[:listen_port] = options[:listen_port]
      content[:cookie] = options[:cookie]
      open(@pid_file,'w') { |f| f.write(YAML.dump(content)) }
      true
    end

    # Delete pid file
    #
    # === Return
    # true:: Always return true
    def remove
      File.delete(@pid_file) if exists?
      true
    end
    
    # Read pid file content
    # Empty hash if pid file does not exist or content cannot be loaded
    # 
    # === Return
    # content(Hash):: Hash containing 3 keys :pid, :cookie and :port
    def read_pid
      content = {}
      open(@pid_file,'r') { |f| content = YAML.load(f.read) rescue {} } if exists?
      content
    end
    
    # Does pid file exist?
    #
    # === Return
    # true:: If pid file exists
    # false:: Otherwise
    def exists?
      File.exists?(@pid_file)
    end

    # Human representation
    #
    # === Return
    # path(String):: Path to pid file
    def to_s
      path = @pid_file
    end
    
    private

    # Check wether there is a process running with the given pid
    #
    # === Parameters
    # pid(Integer):: PID to check
    #
    # === Return
    # true:: If there is a process running with the given pid
    # false: Otherwise
    def process_running?(pid)
      Process.getpgid(pid) != -1
    rescue Errno::ESRCH
      false
    end

  end # PidFile

end # RightScale
