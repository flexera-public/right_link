require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'command_runner'
require 'instance_commands'
require 'command_io'
require 'exceptions'
require 'agent_identity'

describe RightScale::CommandRunner do

  before(:all) do
    RightScale::InstanceCommands.stub!(:get).and_return({})
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1).to_s
    @command_payload = { :name => 'test', :port => 10, :options => 'options' }
  end

  it 'should handle invalid formats' do
    RightScale::CommandIO.stub!(:listen).and_yield(['invalid yaml'])
    RightScale::RightLinkLog.logger.should_receive(:warn).once
    lambda { RightScale::CommandRunner.start(@agent_identity) }.should_not raise_error
  end

  it 'should handle non existant commands' do
    RightScale::CommandIO.stub!(:listen).and_yield(@command_payload)
    RightScale::RightLinkLog.logger.should_receive(:warn).once
    lambda { RightScale::CommandRunner.start(@agent_identity) }.should_not raise_error
  end

  it 'should run commands' do
    commands = { :test => lambda { |opt| @opt = opt } }
    RightScale::InstanceCommands.stub!(:get).and_return(commands)
    RightScale::CommandIO.stub!(:listen).and_yield(@command_payload)
    RightScale::CommandRunner.start(@agent_identity)
    lambda { RightScale::CommandRunner.start(@agent_identity) }.should_not raise_error
    @opt.should == @command_payload
  end

end