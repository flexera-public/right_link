#
# Copyright (c) 2010-2014 RightScale Inc
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
#

module ::Ohai::Mixin::XenstoreMetadata
  def on_windows?
    RUBY_PLATFORM =~ /windows|cygwin|mswin|mingw|bccwin|wince|emx/
  end

  def xenstore_command(command, args)
    if on_windows?
      client = "\"c:\\Program Files\\Citrix\\XenTools\\xenstore_client.exe\""
      if command == "ls"
        command = "dir"
      end
    else
      client = "xenstore"
    end
    command = "#{client} #{command} #{args}"
    begin
      status, stdout, stderr = run_command(:no_status_check => true, :command => command)
      status = status.exitstatus if status.respond_to?(:exitstatus)
    rescue Ohai::Exceptions::Exec => e
      Ohai::Log.debug("xenstore command '#{command}' failed (#{e.class}: #{e.message})")
      stdout = stderr = nil
      status = 1
    end
    [status, stdout, stderr]
  end
end
