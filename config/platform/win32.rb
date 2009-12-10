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
        @@get_temp_dir_api = nil

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
            buffer = 0.chr * 260
            @@get_temp_dir_api.call(buffer.length, buffer)
            @temp_dir = pretty_path(buffer.unpack('A*').first.chomp('\\'))
          end
        rescue
          @temp_dir = File.join(Dir::WINDOWS, "temp")
        ensure
          return @temp_dir
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

        def format_script_file_name(partial_script_file_path, default_extension = POWERSHELL_V1x0_SCRIPT_EXTENSION)
          extension = File.extname(partial_script_file_path)
          if 0 == extension.length
            return partial_script_file_path + default_extension
          end

          return partial_script_file_path
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

    end
  end
end
