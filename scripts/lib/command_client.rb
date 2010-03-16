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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))

module RightScale

  class CommandClient

    # Agent response if any
    attr_accessor :response

    # Send command to running RightLink agent
    #
    # === Parameters
    # options(Hash):: Hash of options and command name
    #   options[:name]:: Command name
    #   options[:...]:: Other command specific options, passed through to agent
    # verbose(Boolean):: Whether client should display debug info
    # timeout(Integer):: Number of seconds we should wait for a reply from the instance agent
    #
    # === Block
    # handler: Command results handler
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # RuntimeError:: Timed out waiting for result
    def send_command(options, verbose=false, timeout=20, &handler)
      EM.error_handler do |e|
        msg = "EM block execution failed with exception: #{e.message}"
        RightLinkLog.error(msg + "\n" + e.backtrace.join("\n"))
      end
      EM.run do
        command = options.dup
        command[:verbose] = verbose
        EM.connect('127.0.0.1', RightScale::CommandConstants::SOCKET_PORT, ConnectionHandler, command, self)
        EM.add_timer(timeout) { EM.stop; raise 'Timed out waiting for instance agent reply' }
      end
      handler.call(@response) if handler && @response
      true
    end

    protected

    # EventMachine connection handler which sends command to instance agent
    # and waits for response
    module ConnectionHandler

      # Initialize command
      #
      # === Parameters
      # command(Hash):: Command to be sent
      # client(RightScale::CommandClient):: Client whose response field should be initialized
      def initialize(command, client)
        @command = command
        @parser = CommandParser.new do |data|
          client.response = data
          EM.stop
        end
      end

      # Send command to instance agent
      # Called by EventMachine after connection with instance agent has been established
      #
      # === Return
      # true:: Always return true
      def post_init
        puts "Sending command #{@command.inspect}" if @command[:verbose]
        send_data(CommandSerializer.dump(@command))
        true
      end

      # Handle agent response
      def receive_data(data)
        @parser.parse_chunk(data)
      end
    end

  end
end
