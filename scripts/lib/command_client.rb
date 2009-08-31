
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'command_protocol', 'lib', 'command_protocol')
require File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'common_lib')

module RightScale

  class CommandClient

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
    # hander: Command results handler
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # RuntimeError:: Could not start listening server or timed out waiting for result
    def send_command(options, verbose=false, timeout=20, &handler)
      port       = CommandConstants::SOCKET_PORT + 1
      listening  = false
      retries    = 0
      error      = nil

      EM.run do
        while !listening && retries < 10 do
          puts "Trying to start server on port #{port}" if verbose
          begin
            options.merge!({ :port => port, :verbose => verbose })
            EM.start_server('127.0.0.1', port, ReplyHandler, options, handler)
            listening = true
          rescue Exception => e
            error = e
            retries += 1
            port += 1
          end
          if listening
            puts "Server listening on port #{port}" if verbose
            EM.connect('127.0.0.1', RightScale::CommandConstants::SOCKET_PORT, SendHandler, options)
            EM.add_timer(timeout) { EM.stop; raise 'Timed out waiting for instance agent reply' }
          else
            EM.stop
          end
        end
      end
      raise "Could not start server: #{error && error.message || 'unknown error'}" unless listening
      true
    end

    protected

    # EventMachine connection handler which sends command to instance agent
    module SendHandler

      # Initialize command
      #
      # === Parameters
      # command<Hash>:: Command to be sent
      def initialize(command)
        @command = command
      end

      # Send command to instance agent
      # Called by EventMachine after connection with instance agent has been established
      #
      # === Return
      # true:: Always return true
      def post_init
        puts "Sending command #{@command.inspect}" if @command[:verbose]
        send_data(CommandSerializer.dump(@command))
        EM.next_tick { close_connection_after_writing }
        true
      end

    end

    # EventMachine connection handler which listens to agent output
    module ReplyHandler

      # Initialize parser
      def initialize(options, handler)
        @options = options
        @handler = handler
        @parser = CommandParser.new { |data| handler.call(data) if handler; EM.stop }
      end

      # Data available callback
      #
      # === Parameters
      # data<String>:: Output data
      #
      # === Return
      # true:: Always return true
      def receive_data(data)
        puts "Received raw data from agent: #{data}" if @options[:verbose]
        @parser.parse_chunk(data)
        true
      end
    end

  end
end
