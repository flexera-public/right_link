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
    flexmock(RightScale::InstanceState).should_receive(:init).and_return(true)
    flexmock(RightScale::InstanceState).should_receive(:value).and_return(instance_state)
    flexmock(RightScale::InstanceState).should_receive(:reboot).and_return(reboot) unless reboot.nil?
    flexmock(RightScale::InstanceState).should_receive(:decommission_type).and_return(decommission_type) unless decommission_type.nil?
    run_state_controller("--type=run")
    @output.join('\n').should include run_state
  end
end

module RightScale
  describe RightLinkStateController do
    def run_state_controller(args)
      replace_argv(args)
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

    context 'rs_state' do
      it 'should fail because no type was specified' do
        flexmock(subject).should_receive(:fail).with("No type specified on the command line.").and_raise(SystemExit)
        run_state_controller([])
      end
    end

    context 'rs_state --type=WRONG' do
      it 'shoud fail because unknow state type was specified' do
        flexmock(subject).should_receive(:fail).with("Unknown state type 'WRONG'. Use 'run' or 'agent'").and_raise(SystemExit)
        run_state_controller("--type=WRONG")
      end
    end

    context 'rs_state --type=agent' do
      it 'should repot agent state (InstanceState.value)' do
        flexmock(InstanceState).should_receive(:init).and_return(true)
        flexmock(InstanceState).should_receive(:value).and_return("AGENT_STATE")
        run_state_controller("--type=agent")
        @output.join("\n").should include "AGENT_STATE"
      end
    end

    context 'rs_state --type=run' do
      context 'should report run state:' do
        create_run_state_example('booting', 'booting', nil, false)
        create_run_state_example('booting:reboot', 'booting', nil, true)
        create_run_state_example('operational', 'operational')
        create_run_state_example('shutting-down:reboot', 'decommissioning', 'reboot')
        create_run_state_example('shutting-down:terminate', 'decommissioning', 'terminate')
        create_run_state_example('shutting-down:stop', 'decommissioning', 'stop')
        create_run_state_example('shutting-down:unknown', 'decommissioning', 'unknown')
      end
    end
  end
end
