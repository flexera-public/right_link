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
    EM.connect('127.0.0.1', RightScale::CommandConstants::SOCKET_PORT, OutputHandler, input)
  end

  it 'should detect missing blocks' do
    lambda { RightScale::CommandIO.listen }.should raise_error(RightScale::Exceptions::Argument)
  end

  it 'should receive a command' do
    @input = ''
    EM.run do
      # note the windows is sensitive to event timing, so use next_tick
      EM.next_tick do
        RightScale::CommandIO.listen { |input, _| @input = input; stop }
        send_input('input')
      end
      EM.add_timer(2) { stop }
    end
    @input.should == 'input'
  end

  it 'should receive many commands' do
    @inputs = []
    EM.run do
      # note the windows is sensitive to event timing, so use next_tick
      EM.next_tick do
        RightScale::CommandIO.listen do |input, _|
           @inputs << input
           stop if input == 'final'
        end
        for i in 1..50 do
          send_input("input#{i}")
        end
        send_input("final")
      end
      EM.add_timer(2) { stop }
    end
    @inputs.size.should == 51
    (0..49).each { |i| @inputs[i].should == "input#{i+1}" }
    @inputs[50].should == 'final'
  end

  def stop
    RightScale::CommandIO.stop_listening
    EM.stop
  end

end
