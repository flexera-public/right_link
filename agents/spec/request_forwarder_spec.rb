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

describe RightScale::RequestForwarder do

  before(:each) do
    RightScale::RequestForwarder.instance.instance_variable_set(:@flushing, false)
    RightScale::RequestForwarder.instance.instance_variable_set(:@requests, [])
    RightScale::RequestForwarder.instance.instance_variable_set(:@mode, :initializing)
    RightScale::RequestForwarder.instance.instance_variable_set(:@stop_flush, false)
    RightScale::RequestForwarder.instance.instance_variable_set(:@vote_timer, nil)
    RightScale::RequestForwarder.instance.instance_variable_set(:@in_init, false)
    RightScale::RequestForwarder.instance.instance_variable_set(:@running, false)
    RightScale::RequestForwarder.instance.instance_variable_set(:@vote_count, 0)
    @mapper_proxy = flexmock('MapperProxy')
    flexmock(RightScale::MapperProxy).should_receive(:instance).and_return(@mapper_proxy)
  end

  it 'should forward requests' do
    @mapper_proxy.should_receive(:request).with('/dummy', 'payload', {:one => 1}).once
    RightScale::RequestForwarder.instance.init
    RightScale::RequestForwarder.instance.request('/dummy', 'payload', {:one => 1})
  end

  it 'should forward pushes' do
    @mapper_proxy.should_receive(:push).with('/dummy', 'payload', {:one => 1}).once
    RightScale::RequestForwarder.instance.init
    RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
  end

  it 'should forward requests done during initialization first' do
    @mapper_proxy.should_receive(:request).with('/first', 'first_payload', {:one => 1}).once.ordered
    @mapper_proxy.should_receive(:request).with('/second', 'second_payload', {:two => 2}, nil).once.ordered
    RightScale::RequestForwarder.instance.request('/second', 'second_payload', {:two => 2})
    RightScale::RequestForwarder.instance.init do
      RightScale::RequestForwarder.instance.request('/first', 'first_payload', {:one => 1})
    end
  end

  it 'should buffer requests in offline mode' do
    EM.run do
      RightScale::RequestForwarder.instance.init
      RightScale::RequestForwarder.instance.enable_offline_mode
      RightScale::RequestForwarder.instance.request('/dummy', 'payload', {:one => 1})
      EM.next_tick { EM.stop }
    end
    RightScale::RequestForwarder.instance.instance_variable_get(:@requests).size.should == 1
  end

  it 'should buffer pushes in offline mode' do
    EM.run do
      RightScale::RequestForwarder.instance.init
      RightScale::RequestForwarder.instance.enable_offline_mode
      RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
      EM.next_tick { EM.stop }
    end
    RightScale::RequestForwarder.instance.instance_variable_get(:@requests).size.should == 1
  end

  it 'should vote for reenroll after the maximum number of in-memory messages is reached' do
    RightScale::RequestForwarder.instance.instance_variable_get(:@vote_count).should == 0
    EM.run do
      RightScale::RequestForwarder.instance.init
      RightScale::RequestForwarder.instance.enable_offline_mode
      RightScale::RequestForwarder.instance.instance_variable_set(:@requests, ('*' * (RightScale::RequestForwarder::MAX_QUEUED_MESSAGES - 1)).split(//))
      RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
      EM.next_tick { EM.stop }
    end
    RightScale::RequestForwarder.instance.instance_variable_get(:@requests).size.should == RightScale::RequestForwarder::MAX_QUEUED_MESSAGES
    RightScale::RequestForwarder.instance.instance_variable_get(:@vote_count).should == 1
  end

  it 'should vote for reenroll after the threshold delay is reached' do
    old_vote_delay = RightScale::RequestForwarder::VOTE_DELAY
    begin
      RightScale::RequestForwarder.const_set(:VOTE_DELAY, 0.1)
      RightScale::RequestForwarder.instance.instance_variable_get(:@vote_count).should == 0
      EM.run do
        RightScale::RequestForwarder.instance.init
        RightScale::RequestForwarder.instance.enable_offline_mode
        RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
        EM.add_timer(0.5) { EM.stop }
      end
      RightScale::RequestForwarder.instance.instance_variable_get(:@vote_count).should == 1
    ensure
      RightScale::RequestForwarder.const_set(:VOTE_DELAY, old_vote_delay)
    end
  end

  it 'should not flush queued in-memory messages until back online' do
    old_flush_delay = RightScale::RequestForwarder::MAX_FLUSH_DELAY
    begin
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, 0.1)
      EM.run do
        RightScale::RequestForwarder.instance.init
        RightScale::RequestForwarder.instance.enable_offline_mode
        RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
        EM.add_timer(0.5) { EM.stop }
      end
    ensure
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, old_flush_delay)
    end
  end

  it 'should flush queued in-memory messages once back online' do
    old_flush_delay = RightScale::RequestForwarder::MAX_FLUSH_DELAY
    @mapper_proxy.should_receive(:push).with('/dummy', 'payload', {:one => 1}).once.and_return { EM.stop }
    begin
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, 0.1)
      EM.run do
        RightScale::RequestForwarder.instance.init
        RightScale::RequestForwarder.instance.enable_offline_mode
        RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
        RightScale::RequestForwarder.instance.disable_offline_mode
        EM.add_timer(1) { EM.stop }
      end
    ensure
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, old_flush_delay)
    end
  end

  it 'should stop flushing when going back to offline mode' do
    old_flush_delay = RightScale::RequestForwarder::MAX_FLUSH_DELAY
    begin
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, 0.1)
      EM.run do
        RightScale::RequestForwarder.instance.init
        RightScale::RequestForwarder.instance.enable_offline_mode
        RightScale::RequestForwarder.instance.push('/dummy', 'payload', {:one => 1})
        RightScale::RequestForwarder.instance.disable_offline_mode
        RightScale::RequestForwarder.instance.instance_variable_get(:@flushing).should be_true
        RightScale::RequestForwarder.instance.instance_variable_get(:@stop_flush).should be_false
        RightScale::RequestForwarder.instance.instance_variable_get(:@mode).should == :offline
        RightScale::RequestForwarder.instance.enable_offline_mode
        RightScale::RequestForwarder.instance.instance_variable_get(:@flushing).should be_true
        RightScale::RequestForwarder.instance.instance_variable_get(:@stop_flush).should be_true
        RightScale::RequestForwarder.instance.instance_variable_get(:@mode).should == :offline
        EM.add_timer(1) do
          RightScale::RequestForwarder.instance.instance_variable_get(:@flushing).should be_false
          RightScale::RequestForwarder.instance.instance_variable_get(:@stop_flush).should be_false
          RightScale::RequestForwarder.instance.instance_variable_get(:@mode).should == :offline
          EM.stop
        end
      end
    ensure
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, old_flush_delay)
    end
  end

end

