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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'command_protocol'))
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
    EM.connect('127.0.0.1', @socket_port, OutputHandler, input)
  end

  before(:all) do
    @socket_port = RightScale::CommandConstants::TEST_SOCKET_PORT
  end

  it 'should detect missing blocks' do
    lambda { RightScale::CommandIO.instance.listen(@socket_port) }.should raise_error(RightScale::Exceptions::Argument)
  end

  it 'should receive a command' do
    @input = ''
    EM.run do
      RightScale::CommandIO.instance.listen(@socket_port) { |input, _| @input = input; stop }
      send_input('input')
      EM.add_timer(2) { stop }
    end
    @input.should == 'input'
  end

  it 'should receive many commands' do
    @inputs = []
    EM.run do
      RightScale::CommandIO.instance.listen(@socket_port) do |input, _|
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
