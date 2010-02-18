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

module RightScale

  class PidFile
    def initialize(identity, options)
      @pid_dir = File.expand_path(options[:pid_dir] || options[:root] || Dir.pwd)
      @pid_file = File.join(@pid_dir, "nanite.#{identity}.pid")
    end
    
    def check
      if pid = read_pid
        if process_running? pid
          raise "#{@pid_file} already exists (pid: #{pid})"
        else
          RightLinkLog.info "removing stale pid file: #{@pid_file}"
          remove
        end
      end
    end
    
    def ensure_dir
      FileUtils.mkdir_p @pid_dir
    end
    
    def write
      ensure_dir
      open(@pid_file,'w') {|f| f.write(Process.pid) }
      File.chmod(0644, @pid_file)
    end
    
    def remove
      File.delete(@pid_file) if exists?
    end
    
    def read_pid
      open(@pid_file,'r') {|f| f.read.to_i } if exists?
    end
    
    def exists?
      File.exists? @pid_file
    end

    def to_s
      @pid_file
    end
    
    private
      def process_running?(pid)
        Process.getpgid(pid) != -1
      rescue Errno::ESRCH
        false
      end

  end # PidFile

end # RightScale