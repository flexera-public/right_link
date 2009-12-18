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
rescue LoadError => e
  raise e if !!(RUBY_PLATFORM =~ /mswin/)
end

require 'fileutils'

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
  end
end


module RightScale
  class Platform
    class Win32

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
        # command_name<String>:: Name of command to be tested with
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
        # command_name<String>:: Name of command to be tested with
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

        def right_scale_state_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'rightscale.d'))
        end

        def spool_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'spool'))
        end

        def cache_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'cache'))
        end

        def log_dir
          return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'log'))
        end

        def temp_dir
          if @temp_dir.nil?
            @@get_temp_dir_api = Windows::API.new('GetTempPath', 'LP', 'L') unless @@get_temp_dir_api
            buffer = 0.chr * MAX_PATH
            @@get_temp_dir_api.call(buffer.length, buffer)
            @temp_dir = pretty_path(buffer.unpack('A*').first.chomp('\\'))
          end
        rescue
          @temp_dir = File.join(Dir::WINDOWS, "temp")
        ensure
          return @temp_dir
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
        # long_path<String>:: fully or partially existing long path to be
        # converted to its short path equivalent.
        #
        # === Return
        # short_path<String>:: short path equivalent or same path if non-existent
        def long_path_to_short_path(long_path)
          @@get_short_path_name = Windows::API.new('GetShortPathName', 'PPL', 'L') unless @@get_short_path_name
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

        # specific to the win32 environment to aid in resolving paths to
        # executables in test scenarios.
        def company_program_files_dir
          return pretty_path(File.join(Dir::PROGRAM_FILES, 'RightScale'))
        end

        # pretties up paths which assists Dir.glob() and Dir[] calls which will
        # return empty if the path contains any \ characters. windows doesn't
        # care (most of the time) about whether you use \ or / in paths. as
        # always, there are exceptions to this rule (such as "del c:/xyz" which
        # fails while "del c:\xyz" succeeds)
        def pretty_path(path)
          return path.gsub("\\", "/")
        end
      end

      class Shell

        POWERSHELL_V1x0_SCRIPT_EXTENSION = ".ps1"
        NULL_OUTPUT_NAME = "nul"

        @@executable_extensions = nil

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

        def format_executable_command(executable_file_path, *arguments)
          escaped = []
          [executable_file_path, arguments].flatten.each do |arg|
            value = arg.to_s
            escaped << (value.index(' ') ? "\"#{value}\"" : value)
          end
          return escaped.join(" ")
        end

        def format_shell_command(shell_script_file_path, *arguments)
          # special case for powershell scripts.
          extension = File.extname(shell_script_file_path)
          if extension && 0 == POWERSHELL_V1x0_SCRIPT_EXTENSION.casecmp(extension)
            escaped = []
            [shell_script_file_path, arguments].flatten.each do |arg|
              value = arg.to_s
              escaped << (value.index(' ') ? "'#{value.gsub("'", "''")}'" : value)
            end

            # execute powershell with Unrestricted execution policy. the issue
            # is that powershell by default will only run digitally-signed
            # scripts.
            #
            # FIX: support digitally signed scripts and/or signing on the fly.
            powershell_command = "&{set-executionpolicy -executionPolicy Unrestricted; &#{escaped.join(" ")}; set-executionPolicy Default; exit $LastExitCode}"
            return format_executable_command("powershell.exe", "-command", powershell_command)
          end

          # execution is based on script extension (.bat, .cmd, .js, .vbs, etc.)
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

      end

      class SSH

        def initialize(platform)
          @platform = platform
        end

        # Store public SSH key into ~/.ssh folder and create temporary script
        # that wraps SSH and uses this key if repository does not have need SSH
        # key for access then return nil
        #
        # === Parameters
        # repo<RightScale::CookbookRepositoryInstantiation>:: cookbook repo
        #
        # === Return
        # "":: in all cases because there is no command to run in windows
        # whether or not the repo is private
        def create_repo_ssh_command(repo)
          return "" unless repo.ssh_key

          # resolve key file path.
          user_profile_dir_path = ENV['USERPROFILE']
          fail unless user_profile_dir_path
          ssh_keys_dir = File.join(user_profile_dir_path, '.ssh')
          FileUtils.mkdir_p(ssh_keys_dir) unless File.directory?(ssh_keys_dir)
          ssh_key_file_path = File.join(ssh_keys_dir, 'id_rsa')

          # (re)create key file. must overwrite any existing credentials in case
          # we are switching repositories and have different credentials for each.
          File.open(ssh_key_file_path, 'w') { |f| f.puts(repo.ssh_key) }

          # we need to create the "known_hosts" file or else the process will
          # halt in windows waiting for a yes/no response to the unknown
          # git host. this is normally handled by specifying
          # "-o StrictHostKeyChecking=no" in the GIT_SSH executable, but it is
          # still a mystery why this doesn't work properly in windows.
          #
          # HACK: we can make a failing GIT_SSH call which does not clone the
          # repository but does silently create the proper "known_hosts" file.
          ssh_temp_dir_path = File.join(@platform.filesystem.temp_dir, 'RightScale', 'ssh_temp')
          (FileUtils.rm_rf(ssh_temp_dir_path) if File.directory?(ssh_temp_dir_path)) rescue nil
          FileUtils.mkdir_p(ssh_temp_dir_path)
          ssh_temp_dir_path = @platform.filesystem.long_path_to_short_path(ssh_temp_dir_path)
          ssh_command_file = File.join(ssh_temp_dir_path, 'ssh.bat')
          File.open(ssh_command_file, 'w') { |f| f.puts("ssh -o StrictHostKeyChecking=no %*") }
          temp_cookbook_dir = File.join(ssh_temp_dir_path, 'temp_cookbook')
          git_command = "git clone --quiet --depth 1 #{repo.url} #{temp_cookbook_dir}"
          git_command = @platform.shell.format_redirect_both(git_command)

          ENV['GIT_SSH']=@platform.filesystem.long_path_to_short_path(ssh_command_file)
          `#{git_command}`
          ENV['GIT_SSH']=nil
          (FileUtils.rm_rf(ssh_temp_dir_path) if File.directory?(ssh_temp_dir_path)) rescue nil

          # we cannot run a SSH command under windows (apparently) but we can
          # run using the defaulted credentials in the user's .ssh directory.
          # this is another good reason why we have our own RightScale account
          # when running under windows. the problem we have is that SSH gives
          # "Exit status 128" in verbose mode when we set GIT_SSH.
          return ""
        end

      end

    end
  end
end
