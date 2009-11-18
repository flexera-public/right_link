require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'request_forwarder'
require 'reenroll_manager'

describe RightScale::RequestForwarder do

  before(:each) do
    RightScale::RequestForwarder.instance_variable_set(:@requests, nil)
    RightScale::RequestForwarder.instance_variable_set(:@flushing, false)
    RightScale::RequestForwarder.instance_variable_set(:@requests, nil)
    RightScale::RequestForwarder.instance_variable_set(:@offline_mode, false)
    RightScale::RequestForwarder.instance_variable_set(:@stop_flush, false)
    RightScale::RequestForwarder.instance_variable_set(:@vote_timer, nil)
    RightScale::RequestForwarder.instance_variable_set(:@vote_count, nil)
    @mapper_proxy = flexmock('MapperProxy')
    flexmock(Nanite::MapperProxy).should_receive(:instance).and_return(@mapper_proxy)
  end

  it 'should forward requests' do
    @mapper_proxy.should_receive(:request).with('/dummy', 'payload', {:one => 1}).once
    RightScale::RequestForwarder.request('/dummy', 'payload', {:one => 1})
  end

  it 'should forward pushes' do
    @mapper_proxy.should_receive(:push).with('/dummy', 'payload', {:one => 1}).once
    RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
  end

  it 'should buffer requests in offline mode' do
    EM.run do
      RightScale::RequestForwarder.enable_offline_mode
      RightScale::RequestForwarder.request('/dummy', 'payload', {:one => 1})
      EM.next_tick { EM.stop }
    end
    RightScale::RequestForwarder.instance_variable_get(:@requests).size.should == 1
  end

  it 'should buffer pushes in offline mode' do
    EM.run do
      RightScale::RequestForwarder.enable_offline_mode
      RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
      EM.next_tick { EM.stop }
    end
    RightScale::RequestForwarder.instance_variable_get(:@requests).size.should == 1
  end

  it 'should vote for reenroll after the maximum number of in-memory messages is reached' do
    RightScale::RequestForwarder.instance_variable_get(:@vote_count).should == nil
    EM.run do
      RightScale::RequestForwarder.enable_offline_mode
      RightScale::RequestForwarder.instance_variable_set(:@requests, ('*' * (RightScale::RequestForwarder::MAX_QUEUED_MESSAGES - 1)).split(//))
      RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
      EM.next_tick { EM.stop }
    end
    RightScale::RequestForwarder.instance_variable_get(:@requests).size.should == RightScale::RequestForwarder::MAX_QUEUED_MESSAGES
    RightScale::RequestForwarder.instance_variable_get(:@vote_count).should == 1
  end

  it 'should vote for reenroll after the threshold delay is reached' do
    old_vote_delay = RightScale::RequestForwarder::VOTE_DELAY
    begin
      RightScale::RequestForwarder.const_set(:VOTE_DELAY, 0.1)
      RightScale::RequestForwarder.instance_variable_get(:@vote_count).should == nil
      EM.run do
        RightScale::RequestForwarder.enable_offline_mode
        RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
        EM.add_timer(0.5) { EM.stop }
      end
      RightScale::RequestForwarder.instance_variable_get(:@vote_count).should == 1
    ensure
      RightScale::RequestForwarder.const_set(:VOTE_DELAY, old_vote_delay)
    end
  end

  it 'should not flush queued in-memory messages until back online' do
    old_flush_delay = RightScale::RequestForwarder::MAX_FLUSH_DELAY
    begin
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, 0.1)
      EM.run do
        RightScale::RequestForwarder.enable_offline_mode
        RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
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
        RightScale::RequestForwarder.enable_offline_mode
        RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
        RightScale::RequestForwarder.disable_offline_mode
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
        RightScale::RequestForwarder.enable_offline_mode
        RightScale::RequestForwarder.push('/dummy', 'payload', {:one => 1})
        RightScale::RequestForwarder.disable_offline_mode
        RightScale::RequestForwarder.instance_variable_get(:@flushing).should be_true
        RightScale::RequestForwarder.instance_variable_get(:@stop_flush).should be_false
        RightScale::RequestForwarder.instance_variable_get(:@offline_mode).should be_true
        RightScale::RequestForwarder.enable_offline_mode
        RightScale::RequestForwarder.instance_variable_get(:@flushing).should be_true
        RightScale::RequestForwarder.instance_variable_get(:@stop_flush).should be_true
        RightScale::RequestForwarder.instance_variable_get(:@offline_mode).should be_true
        EM.add_timer(1) do
          RightScale::RequestForwarder.instance_variable_get(:@flushing).should be_false
          RightScale::RequestForwarder.instance_variable_get(:@stop_flush).should be_false
          RightScale::RequestForwarder.instance_variable_get(:@offline_mode).should be_true
          EM.stop
        end
      end
    ensure
      RightScale::RequestForwarder.const_set(:MAX_FLUSH_DELAY, old_flush_delay)
    end
  end

end

