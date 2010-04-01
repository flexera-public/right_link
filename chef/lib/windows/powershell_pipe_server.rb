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

      NEXT_ACTION_PIPE_NAME = 'next_action_2603D237-3DAE-4ae9-BB68-AF90AB875EFB'
      LAST_EXIT_CODE_KEY = "LastExitCode"
      NEXT_ACTION_KEY = :NextAction

      attr_reader :node
      attr_accessor :verbose

      # === Parameters
      # options(Hash):: A hash of options including the following:
      #
      # queue(Queue):: queue of commands to execute (required).
      #
      # logger(Logger):: logger or nil
      def initialize(options = {})
        raise "Missing required :queue" unless @queue = options[:queue]
        @logger = options[:logger]
        @pipe_eventable = nil
      end

      # Starts the pipe server by creating an asynchronous named pipe. Returns
      # control to the caller after adding the pipe to the event machine.
      def start
        flags = ::Win32::Pipe::ACCESS_DUPLEX | ::Win32::Pipe::OVERLAPPED
        pipe = PipeServer.new(NEXT_ACTION_PIPE_NAME, 0, flags)
        begin
          options = {:target => self,
                     :request_handler => :request_handler,
                     :request_query => :request_query,
                     :pipe => pipe,
                     :logger => @logger}
          @pipe_eventable = EM.attach(pipe, PipeServerHandler, options)
        rescue
          pipe.close rescue nil
          raise
        end
      end

      # Stops the pipe server by detaching the eventable from the event machine.
      def stop
        @pipe_eventable.force_detach if @pipe_eventable
        @pipe_eventable = nil
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
        return false == @queue.empty?
      end

      # Handler for next action requests. Expects complete requests and
      # responses to appear serialized as JSON on individual lines (i.e.
      # delimited by newlines). note that JSON text escapes newline characters
      # within string values and normally only includes whitespace for human-
      # readability.
      #
      # === Parameters
      # request_data(String):: request data
      #
      # === Returns
      # response(String):: true if response is ready
      def request_handler(request_data)
        # assume request_data is a single line with a possible newline trailing.
        request = JSON.load(request_data.chomp)
        if 1 == request.keys.size && request.has_key?(LAST_EXIT_CODE_KEY)
          # pop the next action from the queue.
          return JSON.dump(NEXT_ACTION_KEY => @queue.pop(true)) + "\n";
        end
        raise "Invalid request"
      rescue Exception => e
        return JSON.dump(:Error => "#{e.class}: #{e.message}", :Detail => e.backtrace.join("\n")) + "\n"
      end

    end

  end

end
