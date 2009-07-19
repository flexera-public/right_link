require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'agent_identity'

describe RightScale::AgentIdentity do

  it 'should create a token if none is provided' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1)
    id.token.should_not be_nil
  end

  it 'should create unique tokens' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1)
    id.token.should_not be_nil
    id2 = RightScale::AgentIdentity.new('prefix', 'agent_name', 1)
    id2.token.should_not be_nil
    id.token.should_not == id2.token
  end

  it 'should use preset tokens' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    id.token.should == 'token'
  end

  it 'should serialize' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    id2 = RightScale::AgentIdentity.parse(id.to_s)
    id2.prefix.should == id.prefix
    id2.agent_name.should == id.agent_name
    id2.base_id.should == id.base_id
    id2.token.should == id.token
  end

  it 'should validate' do
    id = RightScale::AgentIdentity.new('prefix', 'agent_name', 1, 'token')
    RightScale::AgentIdentity.valid?(id.to_s).should be_true  
  end

end
