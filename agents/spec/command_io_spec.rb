require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'command_protocol', 'lib', 'command_protocol')
require 'command_io'
require 'exceptions'
require 'ostruct'

describe RightScale::CommandIO do

  module OutputHandler
    def initialize(input)
      @input = input
     end
    def post_init
      send_data(RightScale::CommandSerializer.dump(@input))
      close_connection_after_writing
    end
  end

  # Serialize and send given input to command listener
  def send_input(input)
    EM.connect('0.0.0.0', RightScale::CommandConstants::SOCKET_PORT, OutputHandler, input)
  end

  it 'should detect missing blocks' do
    lambda { RightScale::CommandIO.listen }.should raise_error(RightScale::Exceptions::Argument)
  end

  it 'should receive a command' do
    @input = ''
    EM.run do
      RightScale::CommandIO.listen { |input| @input = input; stop }
      send_input('input')
      EM.add_timer(0.2) { stop }
    end
    @input.should == 'input'
  end

  it 'should receive many commands' do
    @inputs = []
    EM.run do
      RightScale::CommandIO.listen { |input| @inputs << input; stop if input == 'final' }
      for i in 1..50 do
        send_input("input#{i}")
      end
      send_input("final")
      EM.add_timer(1) { stop }
    end
    @inputs.size.should == 51
    (0..49).each { |i| @inputs[i].should == "input#{i+1}" }
    @inputs[50].should == 'final'
  end

  module ReplyHandler
    def initialize(block)
      @callback = block
    end
    def receive_data(data)
      @callback.call(data)
    end
  end

  it 'should send data' do
    EM.run do
      @reply = ''
      EM.start_server('0.0.0.0', RightScale::CommandConstants::SOCKET_PORT + 1, ReplyHandler, lambda { |r| @reply << r })
      RightScale::CommandIO.reply(RightScale::CommandConstants::SOCKET_PORT + 1, 'output')
      EM.add_timer(0.5) { EM.stop }
    end
    @reply.should == RightScale::CommandSerializer.dump('output')
  end

  def stop
    RightScale::CommandIO.stop_listening
    EM.stop
  end

end