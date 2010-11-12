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

describe RightScale::InstanceState do

  include RightScale::SpecHelpers

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
    setup_state
    @state_file = RightScale::InstanceState::STATE_FILE
    @scripts_file = RightScale::InstanceState::SCRIPTS_FILE
    @login_policy_file = RightScale::InstanceState::LOGIN_POLICY_FILE
  end

  after(:all) do
    cleanup_state
  end

  it 'should initialize' do
    RightScale::InstanceState.value.should == 'booting'
    RightScale::InstanceState.identity.should == @identity
  end

  context :init do

    it 'should detect first run' do
      flexmock(File).should_receive(:file?).with(@state_file).and_return(false)
      flexmock(File).should_receive(:file?).with(@scripts_file).and_return(false)
      flexmock(File).should_receive(:file?).with(@login_policy_file).and_return(false)

      RightScale::InstanceState.init(@identity)

      RightScale::InstanceState.value.should == 'booting'
    end

    context('when saved state exists') do
      before(:each) do
        @first_booted_at = Time.at(Time.now.to_i - 5*60).to_i
         # Simulate a successful first boot
        @state = {'value' => 'operational', 'identity' => '1',
                  'uptime' => 120.0, 'booted_at' => @first_booted_at,
                  'reboot' => false, 'startup_tags' => [], 'log_level' => 1,
                  'last_recorded_value' => 'operational', 'retry_record_count' => 0}
        flexmock(RightScale::InstanceState).should_receive(:read_json).with(@state_file).and_return(@state).by_default
      end

      it 'should detect restart after decommission' do
        # Simulate a prior decommission
        @state.merge!('value' => 'decommissioned', 'last_recorded_value' => 'decommissioned')
        flexmock(RightScale::InstanceState).should_receive(:read_json).with(@state_file).and_return(@state).once
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
        flexmock(RightScale::InstanceState).should_receive(:booted_at).and_return(@first_booted_at)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@state_file, Hash).never
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@scripts_file, Array).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).never

        RightScale::InstanceState.init(@identity)

        RightScale::InstanceState.value.should == 'decommissioned'
      end

      it 'should detect restart after crash and record state if needed' do
        # Simulate a prior crash when recorded state did not match local state
        @state.merge!('value' => 'operational', 'last_recorded_value' => 'booting', 'retry_record_count' => 1)
        flexmock(RightScale::InstanceState).should_receive(:read_json).with(@state_file).and_return(@state).once
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
        flexmock(RightScale::InstanceState).should_receive(:booted_at).and_return(@first_booted_at)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@state_file, Hash).never
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@scripts_file, Array).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        RightScale::InstanceState.init(@identity)

        RightScale::InstanceState.value.should == 'operational'
      end

      it 'should detect reboot based on boot time' do
        @rebooted_at = @first_booted_at + 300
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(1.0)
        flexmock(RightScale::InstanceState).should_receive(:booted_at).and_return(@rebooted_at).twice
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@state_file, Hash).once
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@scripts_file, Array).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        RightScale::InstanceState.init(@identity)

        RightScale::InstanceState.identity.should == '1'
        RightScale::InstanceState.value.should == 'booting'
        RightScale::InstanceState.reboot?.should be_true
      end

      it 'should detect reboot based on stored reboot state' do
        @state.merge!('reboot' => true)
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(1.0)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@state_file, Hash).once
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@scripts_file, Array).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        RightScale::InstanceState.init(@identity)

        RightScale::InstanceState.identity.should == '1'
        RightScale::InstanceState.value.should == 'booting'
        RightScale::InstanceState.reboot?.should be_true
      end

      it 'should detect bundled boot' do
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@state_file, Hash)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(@scripts_file, [])
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        RightScale::InstanceState.init('2')

        RightScale::InstanceState.identity.should == '2'
        RightScale::InstanceState.value.should == 'booting'
      end
    end
  end

  context :value= do

    it 'should store state' do
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.init(@identity)
      RightScale::InstanceState.value.should == "operational"
    end

    it 'should record state' do
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "booting"
      RightScale::InstanceState.value.should == "booting"
    end

    it 'should not record state for unrecorded values' do
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).never
      RightScale::InstanceState.value = "decommissioned"
      RightScale::InstanceState.value.should == "decommissioned"
    end

    it 'should store last recorded value after recording state' do
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "booting"
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.last_recorded_value.should == "booting"
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "operational", :agent_identity => "1", :from_state => "booting"}, Proc).
              and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "operational"
    end

    it 'should retry record if there is an error after a delay' do
      flexmock(EM).should_receive("add_timer").with(5, Proc).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to record state/)
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.error_results("error")).once
      RightScale::InstanceState.value = "booting"
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.last_recorded_value.should == "pending"
    end

    it 'should store the last recorded value if returned with the error' do
      flexmock(EM).should_receive("add_timer").with(5, Proc).once
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.error_results({'recorded_state' => "pending", 'message' => "Inconsistent"})).once
      RightScale::InstanceState.last_recorded_value.should == "pending"
      RightScale::InstanceState.value = "booting"
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.last_recorded_value.should == "pending"
    end

    it 'should limit record retries' do
      RightScale::InstanceState.const_set(:MAX_RECORD_STATE_RETRIES, 1)
      flexmock(EM).should_receive("add_timer").with(5, Proc).and_yield.once
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "operational", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.error_results({'recorded_state' => "booting", 'message' => "Inconsistent"})).once
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "operational", :agent_identity => "1", :from_state => "booting"}, Proc).
              and_yield(@results_factory.error_results({'recorded_state' => "booting", 'message' => "Inconsistent"})).once
      RightScale::InstanceState.last_recorded_value.should == "pending"
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "booting"
    end

    it 'should not retry record if recorded state is no longer inconsistent' do
      flexmock(EM).should_receive("add_timer").never
      flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
              with('/state_recorder/record', {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.error_results({'recorded_state' => "booting", 'message' => "Inconsistent"})).once
      RightScale::InstanceState.last_recorded_value.should == "pending"
      RightScale::InstanceState.value = "booting"
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.last_recorded_value.should == "booting"
    end

    it 'should retry record with new state if state has changed since last attempt' do

    end

    it 'should give up retrying recorded state if state has changed to unrecorded value' do

    end

    it 'should raise an exception if the value being set is invalid' do
      lambda do
        RightScale::InstanceState.value = "stopped"
      end.should raise_error(RightScale::Exceptions::Argument)
    end

  end

  it 'should record script execution' do
    RightScale::InstanceState.past_scripts.should be_empty
    RightScale::InstanceState.record_script_execution('test')
    RightScale::InstanceState.past_scripts.should == [ 'test' ]
  end

  it 'should record startup tags when transitioning from booting' do
    flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
            with('/state_recorder/record', {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.init(@identity)
    flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
            with('/state_recorder/record', {:state => "operational", :agent_identity => "1", :from_state => "booting"}, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.startup_tags = [ 'a_tag', 'another_tag' ]
    RightScale::InstanceState.value = 'operational'
    RightScale::InstanceState.startup_tags = nil
    RightScale::InstanceState.init(@identity)
    RightScale::InstanceState.startup_tags.should == [ 'a_tag', 'another_tag' ]
    RightScale::InstanceState.reboot?.should be_false
  end

end
