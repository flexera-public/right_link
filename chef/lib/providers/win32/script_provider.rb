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

require 'fileutils'

require File.expand_path(File.join(File.dirname(__FILE__), 'execute_provider'))

class Chef
  class Provider
    class Win32Script < Chef::Provider::Win32Execute

      # use a unique dir name instead of cluttering temp directory with leftover
      # scripts like the original script provider.
      SCRIPT_TEMP_DIR_PATH = ::File.join(::Dir.tmpdir, "chef-script-DA0A2F57-5BC2-4a6d-81C9-FE118194046F")

      # Allows subclasses to specify a file extension for the script to execute.
      # Some interpreters may require the correct file extension in Windows
      # (e.g. "cmd.exe").
      #
      # === Returns
      # extension(String):: dot-prefixed script file extension (e.g. ".bat") or nil
      def script_file_extension
        return nil
      end

      # Runs the script given as a code resource.
      #
      # === Returns
      # always true
      def action_run
        FileUtils.mkdir_p(SCRIPT_TEMP_DIR_PATH) unless ::File.directory?(SCRIPT_TEMP_DIR_PATH)
        begin
          script_path = ::File.join(SCRIPT_TEMP_DIR_PATH, "chef-script")
          extension = script_file_extension
          (script_path += extension) if extension
          ::File.open(script_path, "w") { |f| f.write(@new_resource.code) }
          @new_resource.command("#{@new_resource.interpreter} #{script_path}")

          # execute script
          super
        ensure
          (FileUtils.rm_rf(SCRIPT_TEMP_DIR_PATH) rescue nil) if ::File.directory?(SCRIPT_TEMP_DIR_PATH)
        end
        true
      end

    end
  end
end

# self-register
Chef::Platform.platforms[:windows][:default].merge!(:script => Chef::Provider::Win32Script,
                                                    :perl   => Chef::Provider::Win32Script,
                                                    :python => Chef::Provider::Win32Script,
                                                    :ruby   => Chef::Provider::Win32Script)
