require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
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
    EM.connect('127.0.0.1', RightScale::CommandConstants::SOCKET_PORT, OutputHandler, input)
  end

  it 'should detect missing blocks' do
    lambda { RightScale::CommandIO.instance.listen }.should raise_error(RightScale::Exceptions::Argument)
  end

  it 'should receive a command' do
    @input = ''
    EM.run do
      RightScale::CommandIO.instance.listen { |input, _| @input = input; stop }
      send_input('input')
      EM.add_timer(2) { stop }
    end
    @input.should == 'input'
  end

  it 'should receive many commands' do
    @inputs = []
    EM.run do
      RightScale::CommandIO.instance.listen do |input, _|
        @inputs << input
        stop if input == 'final'
      end
      for i in 1..50 do
        send_input("input#{i}")
      end
      send_input("final")
      EM.add_timer(2) { stop }
    end

    @inputs.size.should == 51
    (0..49).each { |i| @inputs[i].should == "input#{i+1}" }
    @inputs[50].should == 'final'
  end

  def stop
    RightScale::CommandIO.instance.stop_listening
    EM.stop
  end

end
