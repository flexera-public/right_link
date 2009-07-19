# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

module RightScale

  # EventMachine connection
  # Define event loop callbacks hanlder
  module InputHandler

    # Keep block used to handle incoming data
    #
    # === Parameters
    # handler<Proc>:: Incoming data handler
    def initialize(handler)
      @handler = handler
      @parser = CommandParser.new { |cmd| handler.call(cmd) }
    end

    # EventMachine loop callback called whenever there is data coming from the socket
    #
    # === Parameter
    # data<String>:: Incoming data
    #
    # === Return
    # true:: Always return true
    def receive_data(data)
      @parser.parse_chunk(data)
      true
    end
   
  end

  # Class which allows listening for data and sending data on sockets
  # This allows ohter processes running on the same machine to send commands to
  # the agent without having to go through RabbitMQ.
  class CommandIO

    # Is listener currently waiting for input?
    #
    # === Return
    # true:: If 'listen' was last called
    # false:: Otherwise
    def self.listening
      !@conn.nil?
    end

    # Open command socket and wait for input on it
    # This can only be called again after 'stop_listening' was called
    #
    # === Block
    # The given block should take one argument that will be given the commands sent through the socket
    # Commands should be serialized using RightScale::CommandSerializer.
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # <RightScale::Exceptions::Argument>:: If block is missing
    # <RightScale::Exceptions::Application>:: If +listen+ has already been called and +stop+ hasn't since
    def self.listen &block
      raise Exceptions::Argument, 'Missing listener block' unless block_given?
      raise Exceptions::Application, 'Already listening' if listening
      @conn = EM.start_server('0.0.0.0', RightScale::CommandConstants::SOCKET_PORT, InputHandler, block)
      true
    end

    # Stop listening for commands
    # Do nothing if already stopped
    #
    # === Return
    # true:: If command listener was listening
    # false:: Otherwise
    def self.stop_listening
      res = !@conn.nil?
      if res
        EM.stop_server(@conn)
        @conn = nil
      end
      res
    end

    # Write given data to socket, must be listening
    #
    # === Parameters
    # port<Integer>:: Port command line tool is listening on
    # data<String>:: Data that should be written
    #
    # === Return
    # true:: Always return true
    def self.reply(port, data)
      EM.connect('0.0.0.0', port, ReplyHandler, data)
      true
    end

    # Reply handler module, send reply once connected then close connection
    module ReplyHandler

      # Initialize reply data
      #
      # === Parameter
      # data<String>:: Data to be sent
      def initialize(data)
        @data = data
      end
   
      # Reply and close connection
      #
      # === Return
      # Always return true
      def post_init
        send_data(CommandSerializer.dump(@data))
        close_connection_after_writing
      end
    end

  end

end
