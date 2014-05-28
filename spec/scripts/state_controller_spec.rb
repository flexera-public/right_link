# Copyright (c) 2013 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'state_controller'))

def create_run_state_example(run_state, instance_state, decommission_type=nil, reboot=nil)
  example_title = "'#{run_state}' if InstanceState#value == '#{instance_state}'"
  example_title += " and InstanceState#reboot == #{reboot.to_s}" unless reboot.nil?
  unless decommission_type.nil?
    decommission = "is unset or has unknown value"
    decommission = "== '#{decommission_type}'" if RightScale::ShutdownRequest::LEVELS.include?(decommission_type)
    example_title += " and InstanceState.decommission_type #{decommission}"
  end
  it example_title do
    flexmock(subject).should_receive(:silence_stdout).and_yield
    flexmock(RightScale::InstanceState).should_receive(:init).and_return(true)
    flexmock(RightScale::InstanceState).should_receive(:value).and_return(instance_state)
    flexmock(RightScale::InstanceState).should_receive(:reboot?).and_return(reboot) unless reboot.nil?
    flexmock(RightScale::InstanceState).should_receive(:decommission_type).and_return(decommission_type) unless decommission_type.nil?
    run_state_controller("--type=run")
    @output.join('\n').should include run_state
  end
end

module RightScale
  describe RightLinkStateController do
    let ( :send_successed )       { JSON.dump({:result => 'AGENT_STATE'}) }
    let ( :send_error_message )   { "Something goes wrong" }
    let ( :send_failed )          { JSON.dump({:error => send_error_message}) }

    def run_state_controller(args)
      replace_argv(args)
      flexmock(subject).should_receive(:fail_if_right_agent_is_not_running).and_return(true)
      flexmock(subject).should_receive(:check_privileges).and_return(true)
      subject.control(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    before(:all) do
      # preserve old ARGV for posterity (although it's unlikely that anything
      # would consume it after startup).
      @old_argv = ARGV
    end

    after(:all) do
      # restore old ARGV
      replace_argv(@old_argv)
      @error = nil
      @output = nil
    end

    before(:each) do
      @output = []
      flexmock(subject).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
    end

    context 'type option' do
      let(:short_name)      {'-t'}
      let(:long_name)       {'--type'}
      let(:key)             {:type}
      let(:value)           {'run'}
      let(:expected_value)  {'run'}
      it_should_behave_like 'command line argument'
    end

    context 'rs_state --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'state_controller.rb')))
        run_state_controller('--help')
        @output.join('\n').should include usage
      end
    end

    context 'rs_state should fail when' do
      it 'no type was specified' do
        flexmock(subject).should_receive(:fail).with("No type specified on the command line.").and_raise(SystemExit)
        run_state_controller([])
      end

      it 'unknow state type was specified' do
        flexmock(subject).should_receive(:fail).with("Unknown state type 'WRONG'. Use 'run' or 'agent'").and_raise(SystemExit)
        run_state_controller("--type=WRONG")
      end
    end

    context 'rs_stat --type=agent' do
      it 'should send query' do
        flexmock(subject).should_receive(:send_command).with({:name => "get_instance_state_agent"}, false).and_return(send_successed)
        run_state_controller("--type=agent")
        @output.join("\n").should include "AGENT_STATE"
      end

      it 'should report about error' do
        flexmock(subject).should_receive(:send_command).with({:name => "get_instance_state_agent"}, false).and_return(send_failed)
        flexmock(subject).should_receive(:fail).with(send_error_message).and_raise(SystemExit)
        run_state_controller("--type=agent")
      end
    end

    context 'rs_stat --type=run' do
      it 'should send query' do
        flexmock(subject).should_receive(:send_command).with({:name => "get_instance_state_run"}, false).and_return(send_successed)
        run_state_controller("--type=run")
        @output.join("\n").should include "AGENT_STATE"
      end

      it 'should report about error' do
        flexmock(subject).should_receive(:send_command).with({:name => "get_instance_state_run"}, false).and_return(send_failed)
        flexmock(subject).should_receive(:fail).with(send_error_message).and_raise(SystemExit)
        run_state_controller("--type=run")
      end
    end

  end
end
