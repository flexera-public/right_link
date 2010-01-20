require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'command_runner'
require 'instance_commands'
require 'command_io'
require 'exceptions'
require 'agent_identity'

describe RightScale::CommandRunner do

  before(:all) do
    flexmock(RightScale::InstanceCommands).should_receive(:get).and_return({})
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1).to_s
    @command_payload = { :name => 'test', :options => 'options' }
    @scheduler = flexmock('Scheduler')
    @scheduler.should_ignore_missing
  end

  it 'should handle invalid formats' do
    flexmock(RightScale::CommandIO.instance).should_receive(:listen).and_yield(['invalid yaml'])
    flexmock(RightScale::RightLinkLog).should_receive(:info).once
    RightScale::CommandRunner.start(@agent_identity, @scheduler)
  end

  it 'should handle non existant commands' do
    flexmock(RightScale::CommandIO.instance).should_receive(:listen).and_yield(@command_payload)
    flexmock(RightScale::RightLinkLog).should_receive(:info).once
    RightScale::CommandRunner.start(@agent_identity, @scheduler)
  end

  it 'should run commands' do
    commands = { :test => lambda { |opt, _| @opt = opt } }
    flexmock(RightScale::InstanceCommands).should_receive(:get).twice.and_return(commands)
    flexmock(RightScale::CommandIO.instance).should_receive(:listen).twice.and_yield(@command_payload)
    RightScale::CommandRunner.start(@agent_identity, @scheduler)
    RightScale::CommandRunner.start(@agent_identity, @scheduler)
    @opt.should == @command_payload
  end

end