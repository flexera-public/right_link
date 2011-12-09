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

      # Is this machine running RHEL
      #
      # === Return
      # true:: If Linux distro is RHEL
      # false:: Otherwise
      def rhel?
        distro =~ /RedHatEnterpriseServer/i
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

        class ParserError < Exception; end
        class VolumeError < Exception; end

        def initialize
        end

        # Gets a list of currently visible volumes in the form:
        # [{:device, :label, :uuid, :type, :filesystem}]
        #
        # === Parameters
        # conditions(Hash):: hash of conditions to match, or nil (default)
        #
        # === Return
        # result(Array):: array of volume hashes, or an empty array
        #
        # === Raise
        # VolumeError:: on failure to execute `blkid` to obtain raw output
        # ParserError:: on failure to parse volume list
        def volumes(conditions = nil)
          exit_code, blkid_resp = blocking_popen('blkid')
          raise VolumeError.new("Failed to list volumes exit code = #{exit_code}\nblkid\n#{blkid_resp}") unless exit_code == 0
          return parse_volumes(blkid_resp, conditions)
        end

        # Parses raw output from `blkid` into a hash of volumes
        #
        # The hash will contain the device name with a key of :device, and each key value pair
        # for the device.  In order to keep parity with the Windows VolumeManager.parse_volumes
        # method, the :type key will be duplicated as :filesystem
        #
        # Example of raw output from `blkid`
        #
        # /dev/xvdh1: SEC_TYPE="msdos" LABEL="METADATA" UUID="681B-8C5D" TYPE="vfat"
        # /dev/xvdb1: LABEL="SWAP-xvdb1" UUID="d51fcca0-6b10-4934-a572-f3898dfd8840" TYPE="swap"
        # /dev/xvda1: UUID="f4746f9c-0557-4406-9267-5e918e87ca2e" TYPE="ext3"
        # /dev/xvda2: UUID="14d88b9e-9fe6-4974-a8d6-180acdae4016" TYPE="ext3"
        #
        # === Parameters
        # output_text(String):: raw output from `blkid`
        # conditions(Hash):: hash of conditions to match, or nil (default)
        #
        # === Return
        # result(Array):: array of volume hashes, or an empty array
        #
        # === Raise
        # ParserError:: on failure to parse volume list
        def parse_volumes(output_text, conditions = nil)
          results = []
          output_text.each do |line|
            volume = {}
            line_regex = /^([\/a-z0-9]+):(.*)/
            volmatch = line_regex.match(line)
            raise ParserError.new("Failed to parse volume info from #{line.inspect} using #{line_regex.inspect}") unless volmatch
            volume[:device] = volmatch[1]
            volmatch[2].split(' ').each do |pair|
              pair_regex = /([a-zA-Z_\-]+)=(.*)/
              match = pair_regex.match(pair)
              raise ParserError.new("Failed to parse volume info from #{pair} using #{pair_regex.inspect}") unless match
              volume[:"#{match[1].downcase}"] = match[2].gsub('"', '')
              # Make this as much like the windows output as possible
              if match[1] == "TYPE"
                volume[:filesystem] = match[2].gsub('"', '')
              end
            end
            if conditions
              matched = true
              conditions.each do |key,value|

                unless volume[key] == value
                  matched = false
                  break
                end
              end
              results << volume if matched
            else
              results << volume
            end
          end
          results
        end

        # Mounts a volume (returned by VolumeManager.volumes) to the mountpoint specified.
        #
        # === Parameters
        # volume(Hash):: the volume hash returned by VolumeManager.volumes
        # mountpoint(String):: the exact path where the device will be mounted ex: /mnt
        #
        # === Return
        # always true
        #
        # === Raise
        # ArgumentError:: on invalid parameters
        # VolumeError:: on a failure to mount the device
        def mount_volume(volume, mountpoint)
          raise ArgumentError.new("Invalid volume = #{volume.inspect}") unless volume.is_a?(Hash) && volume[:device]
          exit_code, mount_list_output = blocking_popen('mount')
          raise VolumeError.new("Failed interrogation of current mounts; Exit Status: #{exit_code}\nError: #{mount_list_output}") unless exit_code == 0

          device_match = /^#{volume[:device]} on (.+?)\s/.match(mount_list_output)
          mountpoint_from_device_match = device_match ? device_match[1] : mountpoint
          unless (mountpoint_from_device_match && mountpoint_from_device_match == mountpoint)
            raise VolumeError.new("Attempted to mount volume \"#{volume[:device]}\" at \"#{mountpoint}\" but it was already mounted at #{mountpoint_from_device_match}")
          end

          mountpoint_match = /^(.+?) on #{mountpoint}/.match(mount_list_output)
          device_from_mountpoint_match = mountpoint_match ? mountpoint_match[1] : volume[:device]
          unless (device_from_mountpoint_match && device_from_mountpoint_match == volume[:device])
            raise VolumeError.new("Attempted to mount volume \"#{volume[:device]}\" at \"#{mountpoint}\" but \"#{device_from_mountpoint_match}\" was already mounted there.")
          end

          # The volume is already mounted at the correct mountpoint
          return true if /^#{volume[:device]} on #{mountpoint}/.match(mount_list_output)

          # TODO: Maybe validate that the mountpoint is valid *nix path?
          exit_code, mount_output = blocking_popen("mount -t #{volume[:filesystem].strip} #{volume[:device]} #{mountpoint}")
          raise VolumeError.new("Failed to mount volume to \"#{mountpoint}\" with device \"#{volume[:device]}\"; Exit Status: #{exit_code}\nError: #{mount_output}") unless exit_code == 0
          return true
        end

        # Runs the specified command synchronously using IO.popen
        #
        # === Parameters
        # command(String):: system command to be executed
        #
        # === Return
        # result(Array):: tuple of [exit_code, output_text]
        def blocking_popen(command)
          output_text = ""
          IO.popen(command) do |io|
            output_text = io.read
          end
          return $?.exitstatus, output_text
        end
      end # VolumeManager

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

        # Reboot machine now
        def reboot
          `init 6`
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
