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
#

# RightScale.popen3 allows running external processes aynchronously
# while still capturing their standard and error outputs.
# It relies on EventMachine for most of its internal mechanisms.

require 'eventmachine'

module RightScale

  module StdOutHandler
    def initialize(target, stdout_handler, exit_handler, c, r, w)
      @target = target
      @stdout_handler = stdout_handler
      @exit_handler = exit_handler
      @stderr_eventable = c
      # Just so they don't get GCed before the process goes away
      @read_fd = r
      @write_fd = w
    end

    def receive_data(data)
      @target.method(@stdout_handler).call(data) if @stdout_handler
    end

    def unbind
      # We force the attached stderr handler to go away so that
      # we don't end up with a broken pipe
      @stderr_eventable.force_detach if @stderr_eventable
      @target.method(@exit_handler).call(get_status) if @exit_handler
    end
  end

  module StdErrHandler
    def initialize(target, stderr_handler)
      @target = target
      @stderr_handler = stderr_handler
      @unbound = false
    end

    def receive_data(data)
      @target.method(@stderr_handler).call(data)
    end

    def unbind
      @unbound = true
    end

    def force_detach
      # Use next tick to prevent issue in EM where descriptors list
      # gets out-of-sync when calling detach in an unbind callback
      EM.next_tick { detach unless @unbound }
    end
  end

  # Fork process to run given command asynchronously, hooking all three
  # standard streams of the child process.
  #
  # Stream the command's stdout and stderr to the given handlers. Time-
  # ordering of bytes sent to stdout and stderr is not preserved.
  #
  # Call given exit handler upon command process termination, passing in the
  # resulting Process::Status.
  #
  # All handlers must be methods exposed by the given target.
  def self.popen3(cmd, target, stdout_handler = nil, stderr_handler = nil, exit_handler = nil)
    raise "EventMachine reactor must be started" unless EM.reactor_running?
    EM.next_tick do
      saved_stderr = $stderr.dup
      r, w = Socket::pair(Socket::AF_LOCAL, Socket::SOCK_STREAM, 0)#IO::pipe

      $stderr.reopen w
      c = EM.attach(r, StdErrHandler, target, stderr_handler) if stderr_handler
      EM.popen(cmd, StdOutHandler, target, stdout_handler, exit_handler, c, r, w)
      # Do not close 'w', strange things happen otherwise
      # (command protocol socket gets closed during decommission) 
      $stderr.reopen saved_stderr
    end
  end

end
