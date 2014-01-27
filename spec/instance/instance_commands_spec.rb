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

  describe 'command handlers' do

    before(:each) do
      @commands = RightScale::InstanceCommands.new(@agent_identity, @scheduler, @agent_manager)
    end

    describe "run_recipe command" do

      it 'should execute locally via forwarder' do
        options = {:recipe => "recipe"}
        payload = options.merge(:agent_identity => @agent_identity)
        @sender.should_receive(:send_request).
                with("/forwarder/schedule_recipe", payload, nil, Proc).once
        @commands.send(:run_recipe_command, {:conn => 42, :options => options}).should be_true
      end

      it 'should execute remotely if target tags specified' do
        targets = {:tags => ["tag"], :selector => :all}
        options = {:recipe => "recipe"}
        payload = options.merge(:agent_identity => @agent_identity)
        options.merge!(targets)
        @sender.should_receive(:send_push).
                with("/instance_scheduler/execute", payload, targets).once
        flexmock(RightScale::CommandIO.instance).should_receive(:reply).once
        @commands.send(:run_recipe_command, {:conn => 42, :options => options}).should be_true
      end

    end  # run_recipe command

    describe "run_right_script command" do

      it 'should execute locally via forwarder' do
        options = {:right_script => "right script"}
        payload = options.merge(:agent_identity => @agent_identity)
        @sender.should_receive(:send_request).
                with("/forwarder/schedule_right_script", payload, nil, Proc).once
        @commands.send(:run_right_script_command, {:conn => 42, :options => options}).should be_true
      end

      it 'should execute remotely if target tags specified' do
        targets = {:tags => ["tag"], :selector => :all}
        options = {:right_script => "right script"}
        payload = options.merge(:agent_identity => @agent_identity)
        options.merge!(targets)
        @sender.should_receive(:send_push).
                with("/instance_scheduler/execute", payload, targets).once
        flexmock(RightScale::CommandIO.instance).should_receive(:reply).once
        @commands.send(:run_right_script_command, {:conn => 42, :options => options}).should be_true
      end

    end  # run_right_script command

    describe "audit commands" do

      before(:each) do
        @command_io_connection = flexmock('connection')
        @text = 'some text'
        @thread_name = 'some thread'
        @received_options = {}
        @forwarded_options = {:conn => @command_io_connection, :content => @text, :thread_name => @thread_name, :options => @received_options }
        @audit_cook_stub = flexmock('audit cook stub')
        flexmock(::RightScale::AuditCookStub).should_receive(:instance).and_return(@audit_cook_stub)
      end

      describe 'which leave connection open' do

        before(:each) do
          flexmock(::RightScale::CommandIO.instance).should_receive(:reply).with(@command_io_connection, 'OK', false).once.and_return(true)
        end

        it 'should audit update status' do
          @audit_cook_stub.should_receive(:forward_audit).with(:update_status, @text, @thread_name, @received_options).once.and_return(true)
          @commands.send(:audit_update_status_command, @forwarded_options).should be_true
        end

        it 'should audit create new section' do
          @audit_cook_stub.should_receive(:forward_audit).with(:create_new_section, @text, @thread_name, @received_options).once.and_return(true)
          @commands.send(:audit_create_new_section_command, @forwarded_options).should be_true
        end

        it 'should audit append output' do
          @audit_cook_stub.should_receive(:forward_audit).with(:append_output, @text, @thread_name, @received_options).once.and_return(true)
          @commands.send(:audit_append_output_command, @forwarded_options).should be_true
        end

        it 'should audit append info' do
          @audit_cook_stub.should_receive(:forward_audit).with(:append_info, @text, @thread_name, @received_options).once.and_return(true)
          @commands.send(:audit_append_info_command, @forwarded_options).should be_true
        end

        it 'should audit append error' do
          @audit_cook_stub.should_receive(:forward_audit).with(:append_error, @text, @thread_name, @received_options).once.and_return(true)
          @commands.send(:audit_append_error_command, @forwarded_options).should be_true
        end

      end  # which leave connection open

      describe 'which close connection' do

        before(:each) do
          flexmock(::RightScale::CommandIO.instance).should_receive(:reply).with(@command_io_connection, 'OK').once.and_return(true)
        end

        it 'should audit close connection' do
          @audit_cook_stub.should_receive(:close).with(@thread_name).once.and_return(true)
          @commands.send(:close_connection_command, @forwarded_options).should be_true
        end

      end  # which leave connection open

    end  # audit commands

  end  # command handlers

end  # RightScale::InstanceCommands
