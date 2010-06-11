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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'common', 'lib', 'common'))

module RightScale

  class CommandClient

    # Agent response if any
    attr_accessor :response

    # Create client
    #
    # === Parameters
    # socket_port(Integer):: Socket port on which to connect to agent
    # cookie(String):: Cookie associated with command server
    def initialize(socket_port, cookie)
      @socket_port = socket_port
      @cookie = cookie
      @pending = 0
    end

    # Stop command client 
    #
    # === Block
    # Given block gets called back once last response has been received or timeout
    def stop(&close_handler)
      if @pending > 0
        @close_timeout = EM::Timer.new(@last_timeout) { close_handler.call }
        @close_handler = lambda { @close_timeout.cancel; close_handler.call }
      else
        close_handler.call
      end
    end

    # Send command to running agent
    #
    # === Parameters
    # options(Hash):: Hash of options and command name
    #   options[:name]:: Command name
    #   options[:...]:: Other command specific options, passed through to agent
    # verbose(Boolean):: Whether client should display debug info
    # timeout(Integer):: Number of seconds we should wait for a reply from the agent
    #
    # === Block
    # handler: Command results handler
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # RuntimeError:: Timed out waiting for result, raised in EM thread
    def send_command(options, verbose=false, timeout=20, &handler)
      return if @closing
      @last_timeout = timeout
      manage_em = !EM.reactor_running?
      response_handler = lambda do 
        EM.stop if manage_em
        handler.call(@response) if handler && @response
        @pending -= 1
        @close_handler.call if @close_handler && @pending == 0
      end
      send_handler = lambda do
        @pending += 1
        command = options.dup
        command[:verbose] = verbose
        command[:cookie] = @cookie
        EM.connect('127.0.0.1', @socket_port, ConnectionHandler, command, self, response_handler)
        EM.add_timer(timeout) { EM.stop; raise 'Timed out waiting for agent reply' } if manage_em
      end
      if manage_em
        EM.run { send_handler.call }
      else
        send_handler.call
      end
      true
    end

    protected

    # EventMachine connection handler which sends command to agent
    # and waits for response
    module ConnectionHandler

      # Initialize command
      #
      # === Parameters
      # command(Hash):: Command to be sent
      # client(RightScale::CommandClient):: Client whose response field should be initialized
      # callback(Proc):: Called back after response has been set
      def initialize(command, client, callback)
        @command = command
        @parser = CommandParser.new do |data|
          client.response = data
          callback.call
        end
      end

      # Send command to agent
      # Called by EventMachine after connection with agent has been established
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
