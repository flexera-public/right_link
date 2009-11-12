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

require 'rubygems'
require 'win32/open3'
require 'win32/process'
require 'eventmachine'

module RightScale

  module StdOutHandler

    # quacks like Process::Status, which we cannot instantiate ourselves because
    # has no public new method. RightScale.popen3 needs this because the
    # win32/process gem currently won't return Process::Status objects but only
    # returns a [pid, exitstatus] value.
    class Status
      attr_accessor :pid, :exitstatus

      def initialize(pid, exitstatus)
        @pid = pid
        @exitstatus = exitstatus
      end

      def exited?
        # you can't have this object until the process exits, so...
        return true
      end

      def success?
        return @exitstatus ? (0 == @exitstatus) : true;
      end
    end

    def initialize(target, stdout_handler, exit_handler, stderr_eventable, stream_out, pid)
      @target = target
      @stdout_handler = stdout_handler
      @exit_handler = exit_handler
      @stderr_eventable = stderr_eventable
      @stream_out = stream_out
      @pid = pid
      @status = nil
    end

    def receive_data(data)
      @target.method(@stdout_handler).call(data) if @stdout_handler
    end

    # override of Connection.get_status for win32
    def get_status
      unless @status
        begin
          @status = Status.new(@pid, Process.waitpid2(@pid)[1])
        rescue Process::Error
          # process is gone, which means we have no recourse to retrieve the
          # actual exit code; let's be optimistic.
          @status = Status.new(@pid, 0)
        end
      end
      return @status
    end

    def unbind
      # We force the attached stderr handler to go away so that
      # we don't end up with a broken pipe
      @stderr_eventable.force_detach if @stderr_eventable
      @target.method(@exit_handler).call(get_status) if @exit_handler
      @stream_out.close
    end
  end

  module StdErrHandler
    def initialize(target, stderr_handler, stream_err)
      @target = target
      @stderr_handler = stderr_handler
      @stream_err = stream_err
      @unbound = false
    end

    def receive_data(data)
      @target.method(@stderr_handler).call(data)
    end

    def unbind
      @unbound = true
      @stream_err.close
    end

    def force_detach
      # Use next tick to prevent issue in EM where descriptors list
      # gets out-of-sync when calling detach in an unbind callback
      EM.next_tick { detach unless @unbound }
    end
  end

  def self.popen3(cmd, target, stdout_handler = nil, stderr_handler = nil, exit_handler = nil)
    raise "EventMachine reactor must be started" unless EM.reactor_running?

    # launch cmd and close input immediately.
    stream_in, stream_out, stream_err, pid = Open4.popen4(cmd)
    stream_in.close

    # attach handlers to event machine and let it monitor incoming data. the
    # streams aren't used directly by the connectors except that they are closed
    # on unbind.
    stderr_eventable = EM.attach(stream_err, StdErrHandler, target, stderr_handler, stream_err) if stderr_handler
    EM.attach(stream_out, StdOutHandler, target, stdout_handler, exit_handler, stderr_eventable, stream_out, pid)

    # note that control returns to the caller, but the launched cmd continues
    # running and sends output to the handlers. the caller is not responsible
    # for waiting for the process to terminate or closing streams as the
    # attached eventables will handle this automagically. notification will be
    # sent to the exit_handler on process termination.
  end

  def self.popen25(cmd, target, output_handler = nil, exit_handler = nil)
    raise NotImplementedError
  end

end
