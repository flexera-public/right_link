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

begin
  require 'rubygems'
  require 'win32/dir'
  require 'windows/api'
  require 'win32ole'
rescue LoadError => e
  raise e if !!(RUBY_PLATFORM =~ /mswin/)
end

require 'fileutils'

# ohai 0.3.6 has a bug which causes WMI data to be imported using the default
# Windows code page. the workaround is to set the win32ole gem's code page to
# UTF-8, which is probably a good general Ruby on Windows practice in any case.
WIN32OLE.codepage = WIN32OLE::CP_UTF8

# win32/process monkey-patches the Process class but drops support for any kill
# signals which are not directly portable. some signals are acceptable, if not
# strictly portable, and are handled by the ruby c implementation (such as
# 'TERM') but raise an exception in win32/process. we will monkey-patch the
# monkey-patch to get the best possible implementation of signals.
module Process
  unless defined?(@@ruby_c_kill)
    @@ruby_c_kill = method(:kill)

    fail "Must require platform/win32 before win32/process" unless require 'win32/process'

    @@win32_kill = method(:kill)

    def self.kill(sig, *pids)
      begin
        @@win32_kill.call(sig, *pids)
      rescue Process::Error => e
        begin
          @@ruby_c_kill.call(sig, *pids)
        rescue
          raise e
        end
      end
    end

    # implements getpgid() for Windws
    def self.getpgid(pid)
      # FIX: we currently only use this to check if the process is running.
      # it is possible to get the parent process id for a process in Windows if
      # we actually need this info.
      return Process.kill(0, pid).contains?(pid) ? 0 : -1
    rescue
      raise Errno::ESRCH
    end
  end
end


module RightScale
  class Platform
    class Windows

      class Filesystem
        MAX_PATH = 260

        @@get_temp_dir_api = nil
        @@get_short_path_name = nil

        def initialize
          @temp_dir = nil
        end

        # Is given command available in the PATH?
        #
        # === Parameters
        # command_name(String):: Name of command to be tested with
        # or without the expected windows file extension.
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
        # command_name(String):: Name of command to be tested with
        # or without the expected windows file extension.
        #
        # === Return
        # path to first matching executable file in PATH or nil
        def find_executable_in_path(command_name)
          # must search all known (executable) path extensions unless the
          # explicit extension was given. this handles a case such as 'curl'
          # which can either be on the path as 'curl.exe' or as a command shell
          # shortcut called 'curl.cmd', etc.
          use_path_extensions = 0 == File.extname(command_name).length
          path_extensions = use_path_extensions ? ENV['PATHEXT'].split(/;/) : nil

          # must check the current working directory first just to be completely
          # sure what would happen if the command were executed. note that linux
          # ignores the CWD, so this is platform-specific behavior for windows.
          cwd = Dir.getwd
          path = ENV['PATH']
          path = (path.nil? || 0 == path.length) ? cwd : (cwd + ';' + path)
          path.split(/;/).each do |dir|
            if use_path_extensions
              path_extensions.each do |path_extension|
                path = File.join(dir, command_name + path_extension)
                return path if File.executable?(path)
              end
            else
              path = File.join(dir, command_name)
              return path if File.executable?(path)
            end
          end
          return nil
        end

        # RightScale state directory for the current platform
        def right_scale_state_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'rightscale.d'))
        end

        # Spool directory for the current platform
        def spool_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'spool'))
        end

        # Cache directory for the current platform
        def cache_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'cache'))
        end

        # Log directory for the current platform
        def log_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'log'))
        end

        # Temp directory for the current platform
        def temp_dir
          if @temp_dir.nil?
            @@get_temp_dir_api = Win32::API.new('GetTempPath', 'LP', 'L') unless @@get_temp_dir_api
            buffer = 0.chr * MAX_PATH
            @@get_temp_dir_api.call(buffer.length, buffer)
            @temp_dir = pretty_path(buffer.unpack('A*').first.chomp('\\'))
          end
        rescue
          @temp_dir = File.join(Dir::WINDOWS, "temp")
        ensure
          return @temp_dir
        end

        # System root path
        def system_root
          return pretty_path(ENV['SystemRoot'])
        end

        # converts a long path to a short path. in windows terms, this means
        # taking any file/folder name over 8 characters in length and truncating
        # it to 6 characters with ~1..~n appended depending on how many similar
        # names exist in the same directory. file extensions are simply chopped
        # at three letters. the short name is equivalent for all API calls to
        # the long path but requires no special quoting, etc. the path must
        # exist at least partially for the API call to succeed.
        #
        # === Parameters
        # long_path(String):: fully or partially existing long path to be
        # converted to its short path equivalent.
        #
        # === Return
        # short_path(String):: short path equivalent or same path if non-existent
        def long_path_to_short_path(long_path)
          @@get_short_path_name = Win32::API.new('GetShortPathName', 'PPL', 'L') unless @@get_short_path_name
          if File.exists?(long_path)
            length = MAX_PATH
            while true
              buffer = 0.chr * length
              length = @@get_short_path_name.call(long_path, buffer, buffer.length)
              if length < buffer.length
                break
              end
            end
            return pretty_path(buffer.unpack('A*').first)
          else
            # must get short path for any existing ancestor since child doesn't
            # (currently) exist.
            child_name = File.basename(long_path)
            long_parent_path = File.dirname(long_path)

            # note that root dirname is root itself (at least in windows)
            return long_path if long_path == long_parent_path

            # recursion
            short_parent_path = long_path_to_short_path(File.dirname(long_path))
            return File.join(short_parent_path, child_name)
          end
        end

        # specific to the windows environment to aid in resolving paths to
        # executables in test scenarios.
        def company_program_files_dir
          return pretty_path(File.join(Dir::PROGRAM_FILES, 'RightScale'))
        end

        # pretties up paths which assists Dir.glob() and Dir[] calls which will
        # return empty if the path contains any \ characters. windows doesn't
        # care (most of the time) about whether you use \ or / in paths. as
        # always, there are exceptions to this rule (such as "del c:/xyz" which
        # fails while "del c:\xyz" succeeds)
        #
        # === Parameters
        # path(String):: path to make pretty
        # native_fs_flag(Boolean):: true if path is pretty for native file
        #   system (i.e. file system calls more likely to succeed), false if
        #   pretty for Ruby interpreter (default).
        def pretty_path(path, native_fs_flag = false)
          return native_fs_flag ? path.gsub("/", "\\") : path.gsub("\\", "/")
        end

        # Ensures a local drive location for the file or folder given by path
        # by copying to a local temp directory given by name only if the item
        # does not appear on the home drive. This method is useful because
        # secure applications refuse to run scripts from network locations, etc.
        # Replaces any similar files in temp dir to ensure latest updates.
        #
        # === Parameters
        # path(String):: path to file or directory to be placed locally.
        #
        # temp_dir_name(String):: name (or relative path) of temp directory to
        # use only if the file or folder is not on a local drive.
        #
        # === Returns
        # result(String):: local drive path
        def ensure_local_drive_path(path, temp_dir_name)
          homedrive = ENV['HOMEDRIVE']
          if homedrive && homedrive.upcase != path[0,2].upcase
            local_dir = ::File.join(temp_dir, temp_dir_name)
            FileUtils.mkdir_p(local_dir)
            local_path = ::File.join(local_dir, ::File.basename(path))
            if ::File.directory?(path)
              FileUtils.rm_rf(local_path) if ::File.directory?(local_path)
              FileUtils.cp_r(::File.join(path, '.'), local_path)
            else
              FileUtils.cp(path, local_path)
            end
            path = local_path
          end
          return path
        end

      end

      # Provides utilities for formatting executable shell commands, etc.
      class Shell

        POWERSHELL_V1x0_EXECUTABLE_PATH = "powershell.exe"
        POWERSHELL_V1x0_SCRIPT_EXTENSION = ".ps1"
        NULL_OUTPUT_NAME = "nul"

        @@executable_extensions = nil

        # Formats a script file name to ensure it is executable on the current
        # platform.
        #
        # === Parameters
        # partial_script_file_path(String):: full or partial script file path
        #
        # default_extension(String):: default script extension for platforms
        # which require a known file extension to execute.
        #
        # === Returns
        # executable_script_file_path(String):: executable path
        def format_script_file_name(partial_script_file_path, default_extension = POWERSHELL_V1x0_SCRIPT_EXTENSION)
          extension = File.extname(partial_script_file_path)
          if 0 == extension.length
            return partial_script_file_path + default_extension
          end

          # quick out for default extension.
          if 0 == (extension <=> default_extension)
            return partial_script_file_path
          end

          # confirm that the "extension" is really something understood by
          # the command shell as being executable.
          if @@executable_extensions.nil?
            @@executable_extensions = ENV['PATHEXT'].downcase.split(';')
          end
          if @@executable_extensions.include?(extension.downcase)
            return partial_script_file_path
          end

          # not executable; use default extension.
          return partial_script_file_path + default_extension
        end

        # Formats an executable command by quoting any of the arguments as
        # needed and building an executable command string.
        #
        # === Parameters
        # executable_file_path(String):: full or partial executable file path
        #
        # arguments(Array):: variable stringizable arguments
        #
        # === Returns
        # executable_command(String):: executable command string
        def format_executable_command(executable_file_path, *arguments)
          escaped = []
          [executable_file_path, arguments].flatten.each do |arg|
            value = arg.to_s
            escaped << (value.index(' ') ? "\"#{value}\"" : value)
          end
          return escaped.join(" ")
        end

        # Formats a powershell command using the given script path and arguments.
        # Allows for specifying powershell from a specific installed location.
        # This method is only implemented for Windows.
        #
        # === Parameters
        # shell_script_file_path(String):: shell script file path
        # arguments(Array):: variable stringizable arguments
        #
        # === Returns
        # executable_command(string):: executable command string
        def format_powershell_command(shell_script_file_path, *arguments)
          return format_powershell_command4(POWERSHELL_V1x0_EXECUTABLE_PATH, nil, nil, shell_script_file_path, *arguments)
        end

        # Formats a powershell command using the given script path and arguments.
        # Allows for specifying powershell from a specific installed location.
        # This method is only implemented for Windows.
        #
        # === Parameters
        # powershell_exe_path(String):: path to powershell executable
        # shell_script_file_path(String):: shell script file path
        # arguments(Array):: variable stringizable arguments
        #
        # === Returns
        # executable_command(string):: executable command string
        def format_powershell_command4(powershell_exe_path,
                                       lines_before_script,
                                       lines_after_script,
                                       shell_script_file_path,
                                       *arguments)
          # special case for powershell scripts.
          escaped = []
          [shell_script_file_path, arguments].flatten.each do |arg|
            value = arg.to_s
            escaped << (value.index(' ') ? "'#{value.gsub("'", "''")}'" : value)
          end

          # resolve lines before & after script.
          lines_before_script ||= []
          lines_after_script ||= []

          # execute powershell with Unrestricted execution policy. the issue
          # is that powershell by default will only run digitally-signed
          # scripts.
          # FIX: search for any attempt to alter execution policy in lines
          # before insertion.
          # FIX: support digitally signed scripts and/or signing on the fly by
          # checking for a signature file side-by-side with script.
          lines_before_script.insert(0, "set-executionpolicy -executionPolicy RemoteSigned -Scope Process")
          lines_after_script << "exit $LastExitCode"

          # format powershell command string.
          powershell_command = "&{#{lines_before_script.join("; ")}; &#{escaped.join(" ")}; #{lines_after_script.join("; ")}}"

          # combine command string with powershell executable and arguments.
          return format_executable_command(powershell_exe_path, "-command", powershell_command)
        end

        # Formats a shell command using the given script path and arguments.
        #
        # === Parameters
        # shell_script_file_path(String):: shell script file path
        # arguments(Array):: variable stringizable arguments
        #
        # === Returns
        # executable_command(string):: executable command string
        def format_shell_command(shell_script_file_path, *arguments)
          # special case for powershell scripts.
          extension = File.extname(shell_script_file_path)
          if extension && 0 == POWERSHELL_V1x0_SCRIPT_EXTENSION.casecmp(extension)
            return format_powershell_command(shell_script_file_path, *arguments)
          end

          # execution is based on script extension (.bat, .cmd, .js, .vbs, etc.)
          return format_executable_command(shell_script_file_path, *arguments)
        end

        # Formats a command string to redirect stdout to the given target.
        #
        # === Parameters
        # cmd(String):: executable command string
        #
        # target(String):: target file (optional, defaults to nul redirection)
        def format_redirect_stdout(cmd, target = NULL_OUTPUT_NAME)
          return cmd + " 1>#{target}"
        end

        # Formats a command string to redirect stderr to the given target.
        #
        # === Parameters
        # cmd(String):: executable command string
        #
        # target(String):: target file (optional, defaults to nul redirection)
        def format_redirect_stderr(cmd, target = NULL_OUTPUT_NAME)
          return cmd + " 2>#{target}"
        end

        # Formats a command string to redirect both stdout and stderr to the
        # given target.
        #
        # === Parameters
        # cmd(String):: executable command string
        #
        # target(String):: target file (optional, defaults to nul redirection)
        def format_redirect_both(cmd, target = NULL_OUTPUT_NAME)
          return cmd + " 1>#{target} 2>&1"
        end

        # Gets the current system uptime.
        #
        # === Return
        # the time the machine has been up in seconds, 0 if there was an error.
        def uptime
          begin
            return Time.now.to_f - booted_at.to_f
          rescue Exception
            return 0.0
          end
        end

        # Gets the time at which the system was booted
        #
        # === Return
        # the UTC timestamp at which the system was booted
        def booted_at
          begin
            wmic_output = `echo | wmic OS Get LastBootUpTime`

            match = /(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\.\d{6}([+-]\d{3})/.match(wmic_output)

            year, mon, day, hour, min, sec, tz = match[1..-1]

            #Convert timezone from [+-]mmm to [+-]hh:mm
            tz = "#{tz[0...1]}#{(tz.to_i.abs / 60).to_s.rjust(2,'0')}:#{(tz.to_i.abs % 60).to_s.rjust(2,'0')}"

            #Finally, parse the WMIC output as an XML-schema time, which is the only reliable
            #way to parse a time with arbitrary zone in Ruby (?!)
            return Time.xmlschema("#{year}-#{mon}-#{day}T#{hour}:#{min}:#{sec}#{tz}").to_i
          rescue Exception
            return nil
          end
        end
      end

      class Controller
        # Shutdown machine now
        def shutdown
          # Eww, we can't just call the normal shutdown on 64bit because of bitness
          # Hack that will work on EC2, need to find a better way...
          cmd = "c:\\WINDOWS\\ServicePackFiles\\amd64\\shutdown.exe"
          cmd = 'shutdown.exe' unless File.exists?(cmd)
          `#{cmd} -s -f -t 01`
        end
      end

      class Rng
        def pseudorandom_bytes(count)
          bytes = ''

          srand #to give us a fighting chance at avoiding state-sync issues
          
          count.times do
            bytes << rand(0xff)
          end

          bytes
        end
      end

    end
  end
end

# Platform specific implementation of File.normalize_path
class File

  # First expand the path then shorten the directory.
  # Only shorten the directory and not the file name because 'gem' wants
  # long file names
  def self.normalize_path(file_name, *dir_string)
    @fs ||= RightScale::Platform::Windows::Filesystem.new
    path = File.expand_path(file_name, *dir_string)
    dir = @fs.long_path_to_short_path(File.dirname(path))
    File.join(dir, File.basename(path))
  end

end
