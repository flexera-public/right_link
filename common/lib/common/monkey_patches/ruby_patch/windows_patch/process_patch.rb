#
# Copyright (c) 2011 RightScale Inc
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

require 'rubygems'

# win32/process monkey-patches the Process class but drops support for any kill
# signals which are not directly portable. some signals are acceptable, if not
# strictly portable. the 'TERM' signal used to be supported in Ruby v1.8.6 but
# raises an exception in Ruby v1.8.7. we will monkey-patch the monkey-patch to
# get the best possible implementation of signals.
module Process
  unless defined?(@@ruby_c_kill)
    @@ruby_c_kill = method(:kill)

    # check to ensure this is the first time 'win32/process' has been required
    raise LoadError, "Must require process_patch before win32/process" unless require 'win32/process'

    @@win32_kill = method(:kill)

    def self.kill(sig, *pids)
      sig = 1 if 'TERM' == sig  # Signals 1 and 4-8 kill the process in a nice manner.
      @@win32_kill.call(sig, *pids)
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
