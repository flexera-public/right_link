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
  class Platform
    class Linux
      FEDORA_REL = '/etc/fedora-release'
      FEDORA_SIG = /Fedora release ([0-9]+) \(.*\)/

      attr_reader :distro, :release, :codename

      #Initialize
      def initialize
        system('lsb_release --help > /dev/null 2>&1')

        if $?.success?
          # Use the lsb_release utility if it's available
          @distro  = `lsb_release -is`.strip
          @release =  `lsb_release -rs`.strip
          @codename = `lsb_release -cs`.strip
        elsif File.exist?(FEDORA_REL) && (match = FEDORA_SIG.match(File.read(FEDORA_REL)))
          # Parse the fedora-release file if it exists
          @distro   = 'Fedora'
          @release  = match[1]
          @codename = match[2]
        else
          @distro = @release = @codename = 'unknown'
        end
      end

      # Is this machine running Ubuntu?
      #
      # === Return
      # true:: If Linux distro is Ubuntu
      # false:: Otherwise
      def ubuntu?
        distro =~ /Ubuntu/i
      end

      # Is this machine running CentOS?
      #
      # === Return
      # true:: If Linux distro is CentOS
      # false:: Otherwise
      def centos?
        distro =~ /CentOS/i
      end

      # Is this machine running Suse
      #
      # === Return
      # true:: If Linux distro is Suse
      # false:: Otherwise
      def suse?
        distro =~ /SUSE/i
      end

      class Filesystem

        # Is given command available in the PATH?
        #
        # === Parameters
        # command_name(String):: Name of command to be tested
        #
        # === Return
        # true:: If command is in path
        # false:: Otherwise
        def has_executable_in_path(command_name)
          return nil != find_executable_in_path(command_name)
        end

        # Finds the given command name in the PATH. this emulates the 'which'
        # command from linux (without the terminating newline).
        #
        # === Parameters
        # command_name(String):: Name of command to be tested
        #
        # === Return
        # path to first matching executable file in PATH or nil
        def find_executable_in_path(command_name)
          ENV['PATH'].split(/;|:/).each do |dir|
            path = File.join(dir, command_name)
            return path if File.executable?(path)
          end
          return nil
        end

        def right_scale_state_dir
          '/etc/rightscale.d'
        end

        def spool_dir
          '/var/spool'
        end

        def cache_dir
          '/var/cache'
        end

        def log_dir
          '/var/log'
        end

        def temp_dir
          '/tmp'
        end

        # Path to place pid files
        def pid_dir
          '/var/run'
        end

        # Path to right link configuration and internal usage scripts
        def private_bin_dir
          '/opt/rightscale/bin'
        end

        def sandbox_dir
          '/opt/rightscale/sandbox'
        end

        # for windows compatibility; has no significance in linux
        def long_path_to_short_path(long_path)
          return long_path
        end

        # for windows compatibility; has no significance in linux
        def pretty_path(path, native_fs_flag = false)
          return path
        end

        # for windows compatibility; has no significance in linux
        def ensure_local_drive_path(path, temp_dir_name)
          return path
        end

      end

      # provides utilities for managing volumes (disks).
      class VolumeManager
        def initialize
          raise "not yet implemented"
        end
      end

      class Shell

        NULL_OUTPUT_NAME = "/dev/null"

        def format_script_file_name(partial_script_file_path, default_extension = nil)
          # shell file extensions are not required in linux assuming the script
          # contains a shebang. if not, the error should be obvious.
          return partial_script_file_path
        end

        def format_executable_command(executable_file_path, *arguments)
          escaped = []
          [executable_file_path, arguments].flatten.each do |arg|
            value = arg.to_s
            needs_escape = value.index(" ") || value.index("\"") || value.index("'")
            escaped << (needs_escape ? "\"#{value.gsub("\"", "\\\"")}\"" : value)
          end
          return escaped.join(" ")
        end

        def format_shell_command(shell_script_file_path, *arguments)
          # shell files containing shebang are directly executable in linux, so
          # assume our scripts have shebang. if not, the error should be obvious.
          return format_executable_command(shell_script_file_path, arguments)
        end

        def format_redirect_stdout(cmd, target = NULL_OUTPUT_NAME)
          return cmd + " 1>#{target}"
        end

        def format_redirect_stderr(cmd, target = NULL_OUTPUT_NAME)
          return cmd + " 2>#{target}"
        end

        def format_redirect_both(cmd, target = NULL_OUTPUT_NAME)
          return cmd + " 1>#{target} 2>&1"
        end

        def sandbox_ruby
          "#{RightScale::Platform.filesystem.sandbox_dir}/bin/ruby"
        end

        # Gets the current system uptime.
        #
        # === Return
        # the time the machine has been up in seconds, 0 if there was an error.
        def uptime
          return File.read('/proc/uptime').split(/\s+/)[0].to_f rescue 0.0
        end

        # Gets the time at which the system was booted
        #
        # === Return
        # the UTC timestamp at which the system was booted
        def booted_at
          match = /btime ([0-9]+)/.match(File.read('/proc/stat')) rescue nil

          if match && (match[1].to_i > 0)
            return match[1].to_i
          else
            return nil
          end
        end
      end

      class Controller
        # Shutdown machine now
        def shutdown
          `init 0`
        end
      end

      class Rng
        def pseudorandom_bytes(count)
          f = File.open('/dev/urandom', 'r')
          bytes = f.read(count)
          f.close

          bytes
        end
      end

    end
  end
end

# Platform specific implementation of File.normalize_path
class File

  # On *nix systems, resolves to File.expand_path
  def self.normalize_path(file_name, *dir_string)
    File.expand_path(file_name, *dir_string)
  end

end
