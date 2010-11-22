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

  # Helper method to initialze state with choices :initial_boot and :no_boot
  def init_state(choice = :no_boot, identity = nil)
    rightboot(force_initial_boot = true) if choice == :initial_boot
    RightScale::InstanceState.init(identity || @identity)
  end

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
    @forwarder = flexmock(RightScale::RequestForwarder.instance)
    setup_state('1', false)
    @state_file = RightScale::InstanceState::STATE_FILE
    @login_policy_file = RightScale::InstanceState::LOGIN_POLICY_FILE
  end

  after(:all) do
    cleanup_state
  end

  it 'should initialize' do
    init_state(:initial_boot)
    RightScale::InstanceState.init(@identity)
    RightScale::InstanceState.value.should == 'booting'
    RightScale::InstanceState.identity.should == @identity
  end

  context :init do

    context('when saved state missing') do

      it 'should detect initial boot' do
        flexmock(File).should_receive(:file?).with(@state_file).and_return(false)
        flexmock(File).should_receive(:file?).with(@login_policy_file).and_return(false)

        delete_if_exists(state_file_path)
        init_state

        RightScale::InstanceState.identity.should == '1'
        RightScale::InstanceState.value.should == 'booting'
        RightScale::InstanceState.reboot?.should be_false
      end

    end

    context('when saved state exists') do

      before(:each) do
        # Simulate a successful first boot
        init_state(:initial_boot)
        @state = {'value' => 'operational', 'identity' => '1', 'uptime' => 120.0,
                  'reboot' => false, 'startup_tags' => [], 'log_level' => 1,
                  'last_recorded_value' => 'operational', 'record_retries' => 0,
                  'last_communication' => 0}
        flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).by_default
      end

      it 'should detect restart after decommission' do
        # Simulate a prior decommission
        @state.merge!('value' => 'decommissioned', 'last_recorded_value' => 'decommissioned')
        flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).once
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
        flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).never

        init_state

        RightScale::InstanceState.value.should == 'decommissioned'
      end

      it 'should detect restart after crash and record state if needed' do
        # Simulate a prior crash when recorded state did not match local state
        @state.merge!('value' => 'operational', 'last_recorded_value' => 'booting', 'record_retries' => 1)
        flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).once
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
        flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        init_state

        RightScale::InstanceState.value.should == 'operational'
      end

      it 'should detect reboot based on stored reboot state' do
        # Simulate reboot
        @state.merge!('value' => 'pending', 'reboot' => true)
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(1.0)
        flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).once
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        init_state

        RightScale::InstanceState.identity.should == '1'
        RightScale::InstanceState.value.should == 'booting'
        RightScale::InstanceState.reboot?.should be_true
      end

      it 'should detect bundled boot' do
        flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash)
        flexmock(RightScale::InstanceState).should_receive(:record_state).once

        init_state(:no_boot, '2')

        RightScale::InstanceState.identity.should == '2'
        RightScale::InstanceState.value.should == 'booting'
      end

    end

  end

  context :value= do

    before(:each) do
      @booting_args = ['/state_recorder/record',
                       {:state => "booting", :agent_identity => "1", :from_state => "pending"}, Proc ]
      @operational_args = ['/state_recorder/record',
                           {:state => "operational", :agent_identity => "1", :from_state => "booting"}, Proc ]
      @decommissioning_args = ['/state_recorder/record',
                               {:state => "decommissioning", :agent_identity => "1", :from_state => "operational"}, Proc ]
      @forwarder.should_receive(:request).with(*@booting_args).and_yield(@results_factory.success_results).once
      init_state(:initial_boot)
    end

    it 'should store state' do
      RightScale::InstanceState.value.should == "booting"
      @forwarder.should_receive(:request).with(*@operational_args).and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "operational"
      init_state
      RightScale::InstanceState.value.should == "operational"
      @forwarder.should_receive(:request).with(*@decommissioning_args).and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "decommissioning"
      init_state
      RightScale::InstanceState.value.should == "decommissioning"
    end

    it 'should record state' do
      RightScale::InstanceState.value.should == "booting"
      @forwarder.should_receive(:request).with(*@operational_args).and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      @forwarder.should_receive(:request).with(*@decommissioning_args).and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "decommissioning"
    end

    it 'should not record state for unrecorded values' do
      @forwarder.should_receive(:request).never
      RightScale::InstanceState.value = "decommissioned"
      RightScale::InstanceState.value.should == "decommissioned"
    end

    it 'should store last recorded value after recording state' do
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.last_recorded_value.should == "booting"
      @forwarder.should_receive(:request).with(*@operational_args).and_yield(@results_factory.success_results).once
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "operational"
    end

    it 'should retry record if there is an error after a delay' do
      flexmock(EM).should_receive("add_timer").with(5, Proc).once
      flexmock(RightScale::RightLinkLog).should_receive(:error).with(/Failed to record state/)
      @forwarder.should_receive(:request).with(*@operational_args).and_yield(@results_factory.error_results("error")).once
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "booting"
    end

    it 'should store the last recorded value if returned with an error' do
      flexmock(EM).should_receive("add_timer").with(5, Proc).once
      @forwarder.should_receive(:request).with(*@operational_args).
              and_yield(@results_factory.error_results({'recorded_state' => "pending", 'message' => "Inconsistent"})).once
      RightScale::InstanceState.last_recorded_value.should == "booting"
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "pending"
    end

    it 'should limit record retries' do
      RightScale::InstanceState.const_set(:MAX_RECORD_STATE_RETRIES, 1)
      flexmock(EM).should_receive("add_timer").with(5, Proc).and_yield.once
      @forwarder.should_receive(:request).with(*@operational_args).
              and_yield(@results_factory.error_results({'recorded_state' => "pending", 'message' => "Inconsistent"})).once
      @forwarder.should_receive(:request).
              with('/state_recorder/record', {:state => "operational", :agent_identity => "1", :from_state => "pending"}, Proc).
              and_yield(@results_factory.error_results({'recorded_state' => "pending", 'message' => "Inconsistent"})).once
      RightScale::InstanceState.last_recorded_value.should == "booting"
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "pending"
    end

    it 'should not retry record if recorded state is no longer inconsistent' do
      flexmock(EM).should_receive("add_timer").never
      @forwarder.should_receive(:request).with(*@operational_args).
              and_yield(@results_factory.error_results({'recorded_state' => "operational", 'message' => "Inconsistent"})).once
      RightScale::InstanceState.last_recorded_value.should == "booting"
      RightScale::InstanceState.value = "operational"
      RightScale::InstanceState.value.should == "operational"
      RightScale::InstanceState.last_recorded_value.should == "operational"
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

  context :shutdown do

    it 'should record decommissioned state without specifying last recorded state' do
      flexmock(EM).should_receive(:add_timer).once
      init_state(:initial_boot)
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.value = "decommissioning"
      payload = {:agent_identity => '1', :state => 'decommissioned', :user_id => 123,
                 :skip_db_update => false, :kind => 'terminate'}
      @forwarder.should_receive(:request).with('/state_recorder/record', payload, Proc).once
      RightScale::InstanceState.shutdown(123, false, 'terminate')
    end

    it 'should request removal of queue' do
      flexmock(EM).should_receive(:add_timer).once
      init_state(:initial_boot)
      RightScale::InstanceState.value.should == "booting"
      RightScale::InstanceState.value = "decommissioning"
      payload = {:agent_identity => '1', :state => 'decommissioned', :user_id => 123,
                 :skip_db_update => false, :kind => 'terminate'}
      response = RightScale::Result.new('token', 'to', RightScale::OperationResult.success, 'from')
      @forwarder.should_receive(:request).with('/state_recorder/record', payload, Proc).and_yield(response).once
      @forwarder.should_receive(:push).with('/registrar/remove', {:agent_identity => '1'}).once
      RightScale::InstanceState.shutdown(123, false, 'terminate')
    end

  end

  it 'should update last communication and store it but only if sufficient time has elapsed' do
    init_state(:initial_boot)
    flexmock(RightScale::InstanceState).should_receive(:store_state).once
    RightScale::InstanceState.message_received
    RightScale::InstanceState.message_received
  end

  it 'should always record startup tags' do
    RightScale::InstanceState.startup_tags = [ 'a_tag', 'another_tag' ]
    RightScale::InstanceState.init(@identity)
    RightScale::InstanceState.startup_tags.should == [ 'a_tag', 'another_tag' ]
  end

end
