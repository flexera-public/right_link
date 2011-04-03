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
require File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_deployer')
require File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_controller')

describe AMQP::Client do
  context 'with an incorrect AMQP password' do
    class SUT
      include AMQP::Client

      attr_accessor :reconnecting, :settings, :channels
    end

    before(:each) do
      @sut = flexmock(SUT.new)
      @sut.reconnecting = false
      @sut.settings = {:host=>'testhost', :port=>'12345'}
      @sut.channels = {}

      @sut.should_receive(:initialize)
    end

    context 'and no :reconnect_delay' do
      it 'should reconnect immediately' do
        flexmock(EM).should_receive(:reconnect).once
        flexmock(EM).should_receive(:add_timer).never

        @sut.reconnect()
      end
    end

    context 'and a :reconnect_delay of true' do
      it 'should reconnect immediately' do
        @sut.settings[:reconnect_delay] = true

        flexmock(EM).should_receive(:reconnect).once
        flexmock(EM).should_receive(:add_timer).never

        @sut.reconnect()
      end
    end

    context 'and a :reconnect_delay of 15 seconds' do
      it 'should schedule a reconnect attempt in 15s' do
        @sut.settings[:reconnect_delay] = 15

        flexmock(EM).should_receive(:reconnect).never
        flexmock(EM).should_receive(:add_timer).with(15, Proc).once

        @sut.reconnect()
      end
    end

    context 'and a :reconnect_delay containing a Proc that returns 30' do
      it 'should schedule a reconnect attempt in 30s' do
        @sut.settings[:reconnect_delay] = Proc.new {30}

        flexmock(EM).should_receive(:reconnect).never
        flexmock(EM).should_receive(:add_timer).with(30, Proc).once

        @sut.reconnect()
      end
    end

    context 'and a :reconnect_interval of 5 seconds'  do
      it 'should schedule reconnect attempts on a 5s interval' do
        @sut.reconnecting = true
        @sut.settings[:reconnect_delay] = 15
        @sut.settings[:reconnect_interval] = 5

        flexmock(EM).should_receive(:reconnect).never
        flexmock(EM).should_receive(:add_timer).with(5, Proc).once

        @sut.reconnect()
      end
    end

  end

end
