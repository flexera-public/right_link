#
# Copyright (c) 2009-2011 RightScale Inc
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
require 'right_agent/command'

describe RightScale::InstanceCommands do

  before(:all) do
    @commands = RightScale::InstanceCommands::COMMANDS
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1).to_s
    @scheduler = flexmock('Scheduler')
    @agent_manager = flexmock('AgentManager')
  end

  before(:each) do
    @sender = flexmock('Sender')
    flexmock(RightScale::Sender).should_receive(:instance).and_return(@sender).by_default
  end

  it 'should list commands' do
    flexmock(RightScale::CommandIO.instance).should_receive(:reply).and_return do |conn, r|
      conn.should == 42
      # r is YAML, 2 lines for each command, one less command printed (the list command)
      # plus one header line
      r.count("\n").should == (@commands.reject {|k,_| k.to_s =~ /test/}.size - 1) * 2 + 1
    end
    RightScale::InstanceCommands.new(@agent_identity, @scheduler, @agent_manager).send(:list_command, {:conn => 42}).should be_true
  end

  it 'should get commands' do
    cmds = RightScale::InstanceCommands.get(@agent_identity, @scheduler, @agent_manager)
    cmds.size.should == @commands.size
    cmds.keys.map { |k| k.to_s }.sort.should == @commands.keys.map { |k| k.to_s }.sort
    cmds.values.all? { |v| v.is_a? Proc }.should be_true
  end

  describe "run_recipe command" do

    before(:each) do
      @commands = RightScale::InstanceCommands.new(@agent_identity, @scheduler, @agent_manager)
    end

    it 'should execute locally via forwarder' do
      options = {:recipe => "recipe"}
      payload = options.merge(:agent_identity => @agent_identity)
      @sender.should_receive(:send_persistent_request).
              with("/forwarder/schedule_recipe", payload, nil, Proc).once
      @commands.send(:run_recipe_command, {:conn => 42, :options => options}).should be_true
    end

    it 'should execute remotely if target tags specified' do
      targets = {:tags => ["tag"], :selector => :all}
      options = {:recipe => "recipe"}
      payload = options.merge(:agent_identity => @agent_identity)
      options.merge!(targets)
      @sender.should_receive(:send_persistent_push).
              with("/instance_scheduler/execute", payload, targets).once
      flexmock(RightScale::CommandIO.instance).should_receive(:reply).once
      @commands.send(:run_recipe_command, {:conn => 42, :options => options}).should be_true
    end

  end

  describe "run_right_script command" do

    before(:each) do
      @commands = RightScale::InstanceCommands.new(@agent_identity, @scheduler, @agent_manager)
    end

    it 'should execute locally via forwarder' do
      options = {:right_script => "right script"}
      payload = options.merge(:agent_identity => @agent_identity)
      @sender.should_receive(:send_persistent_request).
              with("/forwarder/schedule_right_script", payload, nil, Proc).once
      @commands.send(:run_right_script_command, {:conn => 42, :options => options}).should be_true
    end

    it 'should execute remotely if target tags specified' do
      targets = {:tags => ["tag"], :selector => :all}
      options = {:right_script => "right script"}
      payload = options.merge(:agent_identity => @agent_identity)
      options.merge!(targets)
      @sender.should_receive(:send_persistent_push).
              with("/instance_scheduler/execute", payload, targets).once
      flexmock(RightScale::CommandIO.instance).should_receive(:reply).once
      @commands.send(:run_right_script_command, {:conn => 42, :options => options}).should be_true
    end

  end

  describe "acquire_thread command" do

    before(:each) do
      @commands = RightScale::InstanceCommands.new(@agent_identity, @scheduler, @agent_manager)
    end

    it 'should acquire thread' do
      mock_connection = 42
      flexmock(::RightScale::CommandIO.instance).should_receive(:reply).once.and_return do |conn, response|
        conn.should == mock_connection
        result = ::RightScale::OperationResult.from_results(::RightScale::Serializer.new.load(response))
        result.success?.should be_true
      end
      thread_name = 'some thread'
      pid = 123
      @scheduler.should_receive(:acquire_thread).with(thread_name, pid).once.and_return(true)
      options = {:conn => mock_connection, :thread_name => thread_name, :pid => pid}
      @commands.send(:acquire_thread_command, options).should be_true
    end

    it 'should respond with retry if thread cannot be acquired from scheduler' do
      mock_connection = 42
      flexmock(::RightScale::CommandIO.instance).should_receive(:reply).once.and_return do |conn, response|
        conn.should == mock_connection
        result = ::RightScale::OperationResult.from_results(::RightScale::Serializer.new.load(response))
        result.retry?.should be_true
      end
      thread_name = 'some thread'
      pid = 123
      @scheduler.should_receive(:acquire_thread).with(thread_name, pid).once.and_return(false)
      options = {:conn => mock_connection, :thread_name => thread_name, :pid => pid}
      @commands.send(:acquire_thread_command, options).should be_true
    end

    it 'should respond with error if thread request is rejected by scheduler' do
      mock_connection = 42
      flexmock(::RightScale::CommandIO.instance).should_receive(:reply).once.and_return do |conn, response|
        conn.should == mock_connection
        result = ::RightScale::OperationResult.from_results(::RightScale::Serializer.new.load(response))
        result.error?.should be_true
      end
      thread_name = 'some thread'
      pid = 123
      @scheduler.should_receive(:acquire_thread).with(thread_name, pid).once.and_raise(ThreadError)
      options = {:conn => mock_connection, :thread_name => thread_name, :pid => pid}
      @commands.send(:acquire_thread_command, options).should be_true
    end

  end  # acquire_thread command

end  # RightScale::InstanceCommands
