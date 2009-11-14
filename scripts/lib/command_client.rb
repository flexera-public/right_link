
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'command_protocol', 'lib', 'command_protocol')
require File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'common_lib')

module RightScale

  class CommandClient

    # Agent response if any
    attr_accessor :response

    # Send command to running RightLink agent
    #
    # === Parameters
    # options<Hash>:: Hash of options and command name
    #   options[:name]:: Command name
    #   options[:...]:: Other command options
    # verbose<Boolean>:: Whether client should display debug info
    # timeout<Integer>:: Number of seconds we should wait for a reply from the instance agent
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
      EM.run do
        EM.connect('127.0.0.1', RightScale::CommandConstants::SOCKET_PORT, ConnectionHandler, options, self)
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
      # command<Hash>:: Command to be sent
      # client<RightScale::CommandClient>:: Client whose response field should be initialized
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
