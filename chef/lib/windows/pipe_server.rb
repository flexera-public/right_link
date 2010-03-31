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
require 'rubygems'
begin
  gem 'eventmachine', '=0.12.8.1'  # patched version for Windows-only socket close fix
rescue Gem::LoadError
  gem 'eventmachine', '=0.12.8'  # notify_readable is deprecated, so currently cannot use >=0.12.10 in Windows gem
end
require 'eventmachine'
require 'win32/pipe'
require 'tempfile'

module RightScale

  module Windows

    # Provides an eventmachine callback handler for the server pipe.
    module PipeServerHandler

      CONNECTING_STATE = 0  # state between client connections
      READING_STATE    = 1  # after connection, receiving request
      WRITING_STATE    = 2  # received request, respond before disconnecting

      SLEEP_DELAY_MSECS = 0.01

      # === Parameters
      # target(Object):: Object defining handler methods to be called.
      #
      # pipe_handler(String):: Token for pipe handler method name.
      #
      # pipe(IO):: pipe object.
      def initialize(target, pipe_handler, pipe, verbose)
        @target = target
        @pipe_handler = pipe_handler
        @pipe = pipe
        @unbound = false
        @state = CONNECTING_STATE
        @data = nil
        @verbose = verbose
      end

      # Callback from EM to asynchronously read the pipe stream. Note that this
      # callback mechanism is deprecated after EM v0.12.8
      def notify_readable
        if @pipe.wait(SLEEP_DELAY_MSECS)
          if @pipe.pending?
            handle_pending
          else
            handle_non_pending
          end
        end
      rescue Exception => e
        puts "#{e.message}\n#{e.backtrace.join("\n")}"
        (disconnect rescue nil) if @state != CONNECTING_STATE
      end

      # Callback from EM to receive data, which we also use to handle the
      # asynchronous data we read ourselves.
      def receive_data(data)
        return @target.method(@pipe_handler).call(data)
      end

      # Callback from EM to unbind.
      def unbind
        puts "unbound" if @verbose
        @pipe.close rescue nil
        @connected = false
        @pipe = nil
        @unbound = true
      end

      # Forces detachment of the handler on EM's next tick.
      def force_detach
        # No need to use next tick to prevent issue in EM where 
        # descriptors list gets out-of-sync when calling detach 
        # in an unbind callback
        detach unless @unbound
      end

      protected

      # Handles any pending I/O from asynchronous pipe server.
      def handle_pending
        case @state
        when CONNECTING_STATE
          puts "connection pending" if @verbose
          connected
          if @pipe.read
            consume_pipe_buffer if not @pipe.pending?
          else
            disconnect
          end
        when READING_STATE
          puts "read pending" if @verbose
          if @pipe.transferred == 0
            disconnect
          else
            consume_pipe_buffer
          end
        when WRITING_STATE
          puts "write pending" if @verbose
          if @pipe.transferred >= @pipe.size
            write_complete
          end
        end

        # sleep a little to allow asynchronous I/O time to complete and
        # avoid busy looping.
        sleep SLEEP_DELAY_MSECS
      end

      # Handles state progression when there is no pending I/O.
      def handle_non_pending
        case @state
        when CONNECTING_STATE
          puts "waiting for connection" if @verbose
          if @pipe.connect
            connected
          end
        when READING_STATE
          puts "still reading request" if @verbose
          if @pipe.read
            consume_pipe_buffer if not @pipe.pending?
          else
            disconnect
          end
        when WRITING_STATE
          puts "done writing request" if @verbose
          write_complete
        end
        # sleep a little to allow asynchronous I/O time to complete and
        # avoid busy looping.
        sleep SLEEP_DELAY_MSECS
      end

      # Acknowledges client connected by changing to reading state.
      def connected
        puts "connected" if @verbose

        # sleep a little to allow asynchronous I/O time to complete and
        # avoid busy looping.
        sleep SLEEP_DELAY_MSECS
        @state = READING_STATE
      end

      # Acknowledges request received by invoking EM receive_data method.
      def read_complete
        puts "read_complete" if @verbose
        if @data && @data.length > 0
          puts "received: #{@data}" if @verbose
          response = receive_data(@data)
          if response && response.length > 0
            puts "writing response = #{response}" if @verbose
            if @pipe.write(response)
              if @pipe.pending?
                @state = WRITING_STATE
              else
                write_complete
              end
            else
              disconnect
            end
          else
            disconnect
          end
        else
          disconnect
        end
        @data = nil
      end

      # Acknowledges response sent by disconnecting and waiting for next client.
      def write_complete
        puts "write_complete" if @verbose
        disconnect
      end

      # Disconnects from client and resumes waiting for next client.
      def disconnect
        puts "disconnect" if @verbose
        @pipe.disconnect
        @state = CONNECTING_STATE
      end

      # Consumes the current contents of the pipe buffer.
      def consume_pipe_buffer
        buffer = @pipe.buffer.clone
        if @data
          @data += buffer
        else
          @data = buffer
        end

        # newline delimits each complete request. the pending flag is not an
        # indication that the complete request has been received because the
        # complete request can be buffered in memory and not be "pending".
        if buffer.index("\n")
          read_complete
        end
      end
    end

    # Provides a generic Windows named pipe server based on eventmachine.
    class PipeServer < ::Win32::Pipe::Server

      # Hack which allows eventmachine to schedule I/O for this non-Ruby IO
      # object. EM needs a real file number, so this method uses a temporary
      # file.
      #
      # === Returns
      # fileno(Integer):: temporary file's file number.
      def fileno
        @temp_file = Tempfile.new("RS-pipe-server") unless @temp_file
        return @temp_file.fileno
      end

      # Hack which fixes a bug with pending write never resetting pending_io
      # flag, causing state machine never to reenter waiting state. also resets
      # buffer which can be set to a small size by a tiny overlapped I/O
      # operation.
      def disconnect
        @pending_io = false
        @buffer     = 0.chr * PIPE_BUFFER_SIZE
        super
      end

      # Closes temporary file before closing pipe.
      def close
        if @temp_file
          @temp_file.close
          @temp_file = nil
        end
        super.close
      end

    end

  end

end
