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
      RESPONDING_STATE = 2  # received request, calculating response
      WRITING_STATE    = 3  # calculated response, respond before disconnecting

      WAIT_SLEEP_DELAY_MSECS = 0.001     # yield to avoid busy looping
      ASYNC_IO_SLEEP_DELAY_MSECS = 0.01  # yield to allow async I/O time to process

      # === Parameters
      # options(Hash):: A hash containing the following options by token name:
      #
      # target(Object):: Object defining handler methods to be called (required).
      #
      # request_handler(Token):: Token for request handler method name (required).
      #
      # request_query(Token):: Token for request query method name if server
      # needs time to calculate a response (allows event loop to continue until
      # such time as request_query returns true).
      #
      # pipe(IO):: pipe object (required).
      #
      # logger(Logger):: logger or nil
      def initialize(options)
        raise "Missing required :target" unless @target = options[:target]
        raise "Missing required :request_handler" unless @request_handler = options[:request_handler]
        raise "Missing require :pipe" unless @pipe = options[:pipe]
        @request_query = options[:request_query]
        @logger = options[:logger]
        @unbound = false
        @state = CONNECTING_STATE
        @data = nil
      end

      # Callback from EM to asynchronously read the pipe stream. Note that this
      # callback mechanism is deprecated after EM v0.12.8
      def notify_readable
        if @state == RESPONDING_STATE || @pipe.wait(WAIT_SLEEP_DELAY_MSECS)
          if @pipe.pending?
            handle_pending
          else
            handle_non_pending
          end

          # sleep a little to allow asynchronous I/O time to complete and
          # avoid busy looping.
          sleep ASYNC_IO_SLEEP_DELAY_MSECS
        end
      rescue Exception => e
        log_error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
        (disconnect rescue nil) if @state != CONNECTING_STATE
      end

      # Callback from EM to receive data, which we also use to handle the
      # asynchronous data we read ourselves.
      def receive_data(data)
        # automagically append a newlineto make it easier to parse response.
        result = @target.method(@request_handler).call(data)
        result += "\n" unless result[-1] == "\n"[0]
        return result
      end

      # Callback from EM to unbind.
      def unbind
        log_debug("unbound")
        @pipe.close rescue nil
        @connected = false
        @pipe = nil
        @unbound = true
      end

      # Forces detachment of the handler unless already unbound.
      def force_detach
        # No need to use next tick to prevent issue in EM where
        # descriptors list gets out-of-sync when calling detach
        # in an unbind callback
        detach unless @unbound
      end

      protected

      # Logs error if enabled
      def log_error(message)
        @logger.error(message) if @logger
      end

      # Logs debug if enabled
      def log_debug(message)
        @logger.debug(message) if @logger
      end

      # Handles any pending I/O from asynchronous pipe server.
      def handle_pending
        case @state
        when CONNECTING_STATE
          log_debug("connection pending")
          connected
          if @pipe.read
            consume_pipe_buffer if not @pipe.pending?
          else
            disconnect
          end
        when READING_STATE
          log_debug("read pending")
          if @pipe.transferred == 0
            disconnect
          else
            consume_pipe_buffer
          end
        when RESPONDING_STATE
          responding
        when WRITING_STATE
          log_debug("write pending")
          if @pipe.transferred >= @pipe.size
            write_complete
          end
        end
      end

      # Handles state progression when there is no pending I/O.
      def handle_non_pending
        case @state
        when CONNECTING_STATE
          log_debug("waiting for connection")
          if @pipe.connect
            connected
          end
        when READING_STATE
          log_debug("still reading request")
          if @pipe.read
            consume_pipe_buffer if not @pipe.pending?
          else
            disconnect
          end
        when RESPONDING_STATE
          responding
        when WRITING_STATE
          log_debug("done writing request")
          write_complete
        end
      end

      # Acknowledges client connected by changing to reading state.
      def connected
        log_debug("connected")

        # sleep a little to allow asynchronous I/O time to complete and
        # avoid busy looping before reading from pipe.
        sleep ASYNC_IO_SLEEP_DELAY_MSECS
        @state = READING_STATE
      end

      # Acknowledges request received by invoking EM receive_data method.
      def read_complete
        log_debug("read_complete")
        if @data && @data.length > 0
          log_debug("received: #{@data}")
          @state = RESPONDING_STATE
        else
          disconnect
        end
      end

      # Determines if the server implementation requires a callback to see if
      # a response is available of if the response must be delayed. In the latter
      # case, the event machine is allowed to continue until the request_query
      # method returns true.
      def responding
        respond if (@request_query.nil? || @target.method(@request_query).call(@data))
      end

      # Asks the server implementation for the calculated response and puts it
      # on the wire.
      def respond
        response = receive_data(@data)
        @data = nil
        if response && response.length > 0
          log_debug("writing response = #{response}")
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
      end

      # Acknowledges response sent by disconnecting and waiting for next client.
      def write_complete
        log_debug("write_complete")
        disconnect
      end

      # Disconnects from client and resumes waiting for next client.
      def disconnect
        log_debug("disconnect")
        @pipe.disconnect
        @state = CONNECTING_STATE
        @data = nil
      end

      # Consumes the current contents of the pipe buffer.
      def consume_pipe_buffer
        buffer = @pipe.buffer.clone
        log_debug("before consume @data = #{@data}")
        if @data
          @data += buffer
        else
          @data = buffer
        end
        log_debug("after consume @data = #{@data}")

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
