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