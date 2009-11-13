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
        # exe<String>:: Name of command to be tested
        #
        # === Return
        # true:: If command is in path
        # false:: Otherwise
        def has_executable_in_path(exe)
          found = false
          exe += '.exe' unless exe =~ /\.exe$/
          ENV['PATH'].split(/;|:/).each do |dir|
            found = File.executable?(File.join(dir, exe))
            break if found
          end
          found
        end

        def right_scale_state_dir
          File.join(Dir::COMMON_APPDATA, 'RightScale', 'rightscale.d')
        end

        def spool_dir
          File.join(Dir::COMMON_APPDATA, 'RightScale', 'spool')
        end

        def cache_dir
          File.join(Dir::COMMON_APPDATA, 'RightScale', 'cache')
        end

        def log_dir
          File.join(Dir::COMMON_APPDATA, 'RightScale', 'log')
        end

        def temp_dir
          if @temp_dir.nil?
            @@get_temp_dir_api = Windows::API.new('GetTempPath', 'LP', 'L') unless @@get_temp_dir_api
            buffer = 0.chr * 260
            @@get_temp_dir_api.call(buffer.length, buffer)
            @temp_dir = buffer.unpack('A*').first.chomp('\\')
          end
        rescue
          @temp_dir = File.join(Dir::WINDOWS, "temp")
        ensure
          return @temp_dir
        end

        # specific to the win32 environment to aid in resolving paths to
        # executables in test scenarios.
        def company_program_files_dir
          File.join(Dir::PROGRAM_FILES, 'RightScale')
        end
      end

      class Shell

        POWERSHELL_V1x0_SCRIPT_EXTENSION = ".ps1"

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
            powershell_command = "&{set-executionpolicy -executionPolicy Unrestricted; &#{escaped.join(" ")}; set-executionPolicy Default}"
            return format_executable_command("powershell.exe", "-command", powershell_command)
          end

          # execution is based on script extension (.bat, .cmd, .js, .vbs, etc.)
          return format_executable_command(shell_script_file_path, arguments)
        end

      end

    end
  end
end
