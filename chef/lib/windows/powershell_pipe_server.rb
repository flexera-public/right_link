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
require File.normalize_path(File.join(File.dirname(__FILE__), 'pipe_server'))
require 'json'
require 'set'

module RightScale

  module Windows

    # Provides a server for a named pipe connection which serves a series of
    # commands to be executed in the powershell context. The final command is
    # expected to be an "exit" statement.
    class PowershellPipeServer

      # Request hash key associated with previous execution exit code
      LAST_EXIT_CODE_KEY = "LastExitCode"

      # Response hash key associated with action to run
      NEXT_ACTION_KEY = :NextAction

      # Initialize pipe server
      #
      # === Parameters
      # options[:pipe_name](String):: Name of pipe to connect to (required)
      #
      # === Block
      # Given block gets called back for each request
      # It should take two arguments:
      #   * First argument is either :is_ready or :respond
      #     calls with :is_ready should return a boolean value set to true if there is a pending command
      #     calls with :respond should return the pending command
      #   * Second argument contains the request data (only set with :respond)
      def initialize(options = {}, &callback)
        raise ArgumentError, "Missing required :pipe_name" unless @pipe_name = options[:pipe_name]
        @callback = callback
        @pipe_eventable = nil
      end

      # Starts the pipe server by creating an asynchronous named pipe. Returns
      # control to the caller after adding the pipe to the event machine.
      #
      # === Return
      # true:: If server was successfully started
      # false:: Otherwise
      def start
        flags = ::Win32::Pipe::ACCESS_DUPLEX | ::Win32::Pipe::OVERLAPPED
        pipe  = PipeServer.new(@pipe_name, 0, flags)
        res   = true
        begin
          options = {:target => self,
                     :request_handler => :request_handler,
                     :request_query => :request_query,
                     :pipe => pipe}
          @pipe_eventable = EM.watch(pipe, PipeServerHandler, options)
          @pipe_eventable.notify_readable = true
        rescue Exception => e
          pipe.close rescue nil
          Chef::Log.error("Failed to start pipe server: #{e.message} from\n#{e.backtrace.join("\n")}")
          res = false
        end
        res
      end

      # Stops the pipe server by detaching the eventable from the event machine.
      #
      # === Return
      # true:: Always return true
      def stop
        @pipe_eventable.force_detach if @pipe_eventable
        @pipe_eventable = nil
        true
      end

      # Ready to respond if the next action queue is empty, otherwise continue
      # blocking client.
      #
      # === Parameters
      # request_data(String):: request data
      #
      # === Returns
      # result(Boolean):: true if response is ready
      def request_query(request_data)
        return @callback.call(:is_ready, nil)
      end

      # Handler for next action requests. Expects complete requests and
      # responses to appear serialized as JSON on individual lines (i.e.
      # delimited by newlines). note that JSON text escapes newline characters
      # within string values and normally only includes whitespace for human-
      # readability.
      #
      # === Parameters
      # request_data(String):: Request data
      #
      # === Returns
      # response(String):: Request response
      def request_handler(request_data)
        # assume request_data is a single line with a possible newline trailing.
        request = JSON.load(request_data.chomp)
        if 1 == request.keys.size && request.has_key?(LAST_EXIT_CODE_KEY)
          # pop the next action from the queue.
          command = @callback.call(:respond, request_data)
          return JSON.dump(NEXT_ACTION_KEY => command) + "\n";
        end
        raise ArgumentError, "Invalid request"
      rescue Exception => e
        return JSON.dump(:Error => "#{e.class}: #{e.message}", :Detail => e.backtrace.join("\n")) + "\n"
      end

    end

  end

end
