require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'reenroll_manager'

describe RightScale::ReenrollManager do

  before(:each) do
    RightScale::ReenrollManager.instance_variable_set(:@total_votes, nil)
    mapper_proxy = flexmock('MapperProxy')
    flexmock(RightScale::MapperProxy).should_receive(:instance).and_return(mapper_proxy)
    mapper_proxy.should_receive(:push)
  end

  it 'should allow voting for reenroll' do
    EM.run do
      RightScale::ReenrollManager.vote
      RightScale::ReenrollManager.instance_variable_get(:@total_votes).should == 1
      EM.stop
    end
  end

  it 'should allow resetting the votes count' do
    EM.run do
      RightScale::ReenrollManager.vote
      RightScale::ReenrollManager.instance_variable_get(:@total_votes).should == 1
      RightScale::ReenrollManager.reset_votes
      RightScale::ReenrollManager.instance_variable_get(:@total_votes).should == 0
      EM.stop
    end
  end

  it 'should reenroll after threshold is reached' do
    flexmock(RightScale::ReenrollManager).should_receive(:system).with('rs_reenroll').once
    EM.run do
      (1..RightScale::ReenrollManager::REENROLL_THRESHOLD).each { RightScale::ReenrollManager.vote }
      RightScale::ReenrollManager.vote
      EM.stop
    end
  end

  it 'should reset the number of votes eventually' do
    old_reset_delay = RightScale::ReenrollManager::RESET_DELAY
    begin
      RightScale::ReenrollManager.const_set(:RESET_DELAY, 0.1)
      EM.run do
        (1..RightScale::ReenrollManager::REENROLL_THRESHOLD).each { RightScale::ReenrollManager.vote }
        RightScale::ReenrollManager.instance_variable_get(:@total_votes).should == RightScale::ReenrollManager::REENROLL_THRESHOLD
        EM.add_timer(0.5) do
          RightScale::ReenrollManager.instance_variable_get(:@total_votes).should == 0
          EM.stop
        end
      end
    ensure
      RightScale::ReenrollManager.const_set(:RESET_DELAY, old_reset_delay )
    end
  end

end

