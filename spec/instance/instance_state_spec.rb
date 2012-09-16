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

describe RightScale::InstanceState do

  include RightScale::SpecHelper

  before(:each) do
    # Avoid actually updating MOTD or performing wall broadcasts
    flexmock(RightScale::InstanceState).should_receive(:update_motd).and_return(nil)
    flexmock(RightScale::InstanceState).should_receive(:broadcast_wall).and_return(nil)

    flexmock(RightScale::Log).should_receive(:debug)
    setup_state(identity = '1', mock_instance_state = false) do
      @user_id = 123
      @booting_args = ['/state_recorder/record',
                       {:state => "booting", :agent_identity => @identity, :from_state => "pending"},
                       nil,
                       Proc]
      @operational_args = ['/state_recorder/record',
                           {:state => "operational", :agent_identity => @identity, :from_state => "booting"},
                           nil,
                           Proc]
      @decommissioning_args = ['/state_recorder/record',
                               {:state => "decommissioning", :agent_identity => @identity, :from_state => "operational"},
                               nil,
                               Proc]
      @decommissioned_args = ['/state_recorder/record',
                              {:state => 'decommissioned', :agent_identity => @identity, :user_id => @user_id,
                               :skip_db_update => false, :kind => "terminate"},
                              Proc]
      @record_success = @results_factory.success_results
      @sender = flexmock(RightScale::Sender.instance)
      @sender.should_receive(:send_retryable_request).with(*@booting_args).and_yield(@record_success).by_default
      @sender.should_receive(:send_retryable_request).and_yield(@record_success).by_default
    end
    @state_file = RightScale::InstanceState::STATE_FILE
    @login_policy_file = RightScale::InstanceState::LOGIN_POLICY_FILE
  end

  after(:all) do
    cleanup_state
  end

  it 'should initialize' do
    run_em_test do
      RightScale::InstanceState.init(@identity)
      RightScale::InstanceState.value.should == 'booting'
      RightScale::InstanceState.identity.should == @identity
      EM.stop
    end
  end

  context :init do

    context('when saved state missing') do

      it 'should detect initial boot' do
        run_em_test do
          flexmock(File).should_receive(:file?).with(@state_file).and_return(false)
          flexmock(File).should_receive(:file?).with(@login_policy_file).and_return(false)

          delete_if_exists(state_file_path)
          RightScale::InstanceState.init(@identity)

          RightScale::InstanceState.identity.should == @identity
          RightScale::InstanceState.value.should == 'booting'
          RightScale::InstanceState.reboot?.should be_false
          EM.stop
        end
      end

    end

    context('when saved state exists') do

      # Using this method instead of before(:each) because must be running EM
      # before InstanceState.init is called
      def before_each
        # Simulate a successful first boot
        RightScale::InstanceState.init(@identity)
        @state = {'value' => 'operational', 'identity' => @identity, 'uptime' => 120.0,
                  'reboot' => false, 'startup_tags' => [], 'log_level' => 1,
                  'last_recorded_value' => 'operational', 'record_retries' => 0,
                  'last_communication' => 0}
        flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).by_default
      end

      it 'should detect restart after decommission' do
        run_em_test do
          before_each
          # Simulate a prior decommission
          @state.merge!('value' => 'decommissioned', 'last_recorded_value' => 'decommissioned')
          flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).once
          flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
          flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).never
          flexmock(RightScale::InstanceState).should_receive(:record_state).never

          RightScale::InstanceState.init(@identity)

          RightScale::InstanceState.value.should == 'decommissioned'
          EM.stop
        end
      end

      it 'should detect restart after crash and record state if needed' do
        run_em_test do
          before_each
          # Simulate a prior crash when recorded state did not match local state
          @state.merge!('value' => 'operational', 'last_recorded_value' => 'booting', 'record_retries' => 1)
          flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).once
          flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
          flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).never
          flexmock(RightScale::InstanceState).should_receive(:record_state).once

          RightScale::InstanceState.init(@identity)

          RightScale::InstanceState.value.should == 'operational'
          EM.stop
        end
      end

      it 'should not record state if in read-only mode' do
        run_em_test do
          before_each
          # Simulate a prior crash when recorded state did not match local state
          @state.merge!('value' => 'operational', 'last_recorded_value' => 'booting', 'record_retries' => 1)
          flexmock(RightScale::JsonUtilities).should_receive(:read_json).with(@state_file).and_return(@state).once
          flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
          flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).never
          flexmock(RightScale::InstanceState).should_receive(:record_state).never

          RightScale::InstanceState.init(@identity, read_only = true)

          RightScale::InstanceState.value.should == 'operational'
          EM.stop
        end
      end

      it 'should detect reboot based on stored reboot state' do
        run_em_test do
          before_each
          # Simulate reboot
          @state.merge!('value' => 'booting', 'reboot' => true)
          flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(1.0)
          flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash).once
          flexmock(RightScale::InstanceState).should_receive(:record_state).once

          RightScale::InstanceState.init(@identity)

          RightScale::InstanceState.identity.should == @identity
          RightScale::InstanceState.value.should == 'booting'
          RightScale::InstanceState.reboot?.should be_true
          EM.stop
        end
      end

      it 'should detect bundled boot' do
        run_em_test do
          before_each
          flexmock(RightScale::JsonUtilities).should_receive(:write_json).with(@state_file, Hash)
          flexmock(RightScale::InstanceState).should_receive(:record_state).once

          RightScale::InstanceState.init('2')

          RightScale::InstanceState.identity.should == '2'
          RightScale::InstanceState.value.should == 'booting'
          EM.stop
        end
      end

    end

  end

  context :value= do

    it 'should store state' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "operational"
        @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "decommissioning"
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "decommissioning"
        RightScale::InstanceState.decommission_type.should == nil
        EM.stop
      end
    end

    it 'should record state' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "decommissioning"
        RightScale::InstanceState.value.should == "decommissioning"
        RightScale::InstanceState.decommission_type.should == nil
        EM.stop
      end
    end

    it 'should persist decommissioning state with decommission type if specified' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        @sender.should_receive(:send_retryable_request).with(*@decommissioning_args).and_yield(@record_success).once
        RightScale::InstanceState.decommission_type = RightScale::ShutdownRequest::REBOOT
        RightScale::InstanceState.value.should == "decommissioning"
        RightScale::InstanceState.decommission_type.should == RightScale::ShutdownRequest::REBOOT

        # reinitialize from state file to simulate aborted decommission case.
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "decommissioning"
        RightScale::InstanceState.last_recorded_value.should == "decommissioning"
        RightScale::InstanceState.decommission_type.should == RightScale::ShutdownRequest::REBOOT
        EM.stop
      end
    end

    it 'should not record state for unrecorded values' do
      run_em_test do
        @sender.should_receive(:send_retryable_request).never
        RightScale::InstanceState.value = "decommissioned"
        RightScale::InstanceState.value.should == "decommissioned"
        EM.stop
      end
    end

    it 'should store last recorded value after recording state' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        RightScale::InstanceState.last_recorded_value.should == "booting"
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        RightScale::InstanceState.last_recorded_value.should == "operational"
        EM.stop
      end
    end

    it 'should retry record after a delay if there is an error' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        flexmock(EM).should_receive("add_timer").with(RightScale::IdempotentRequest::DEFAULT_TIMEOUT, Proc).once
        flexmock(EM).should_receive("add_timer").with(RightScale::InstanceState::RETRY_RECORD_STATE_DELAY, Proc).once
        flexmock(RightScale::Log).should_receive(:error).with(/Failed to record state/)
        error = @results_factory.error_results("error")
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(error).once
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        RightScale::InstanceState.last_recorded_value.should == "booting"
        EM.stop
      end
    end

    it 'should store the last recorded value if returned with the error' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        flexmock(EM).should_receive("add_timer").with(RightScale::IdempotentRequest::DEFAULT_TIMEOUT, Proc).once
        flexmock(EM).should_receive("add_timer").with(RightScale::InstanceState::RETRY_RECORD_STATE_DELAY, Proc).once
        error = @results_factory.error_results({'recorded_state' => "pending", 'message' => "Inconsistent"})
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(error).once
        RightScale::InstanceState.last_recorded_value.should == "booting"
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        RightScale::InstanceState.last_recorded_value.should == "pending"
        EM.stop
      end
    end

    it 'should limit record retries' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.const_set(:MAX_RECORD_STATE_RETRIES, 1)
        flexmock(EM).should_receive("add_timer").with(RightScale::IdempotentRequest::DEFAULT_TIMEOUT, Proc).twice
        flexmock(EM).should_receive("add_timer").with(RightScale::InstanceState::RETRY_RECORD_STATE_DELAY, Proc).and_yield.once
        error = @results_factory.error_results({'recorded_state' => "pending", 'message' => "Inconsistent"})
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(error).once
        @sender.should_receive(:send_retryable_request).with('/state_recorder/record', {:state => "operational",
                :agent_identity => "1", :from_state => "pending"}, nil, Proc).and_yield(error).once
        RightScale::InstanceState.last_recorded_value.should == "booting"
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        RightScale::InstanceState.last_recorded_value.should == "pending"
        EM.stop
      end
    end

    it 'should not retry record if recorded state is no longer inconsistent' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        flexmock(EM).should_receive("add_timer").once
        error = @results_factory.error_results({'recorded_state' => "operational", 'message' => "Inconsistent"})
        @sender.should_receive(:send_retryable_request).with(*@operational_args).and_yield(error).once
        RightScale::InstanceState.last_recorded_value.should == "booting"
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.value.should == "operational"
        RightScale::InstanceState.last_recorded_value.should == "operational"
        EM.stop
      end
    end

    it 'should cancel running record state request before running another' do
      run_em_test do
        decommissioning_args = ['/state_recorder/record',
                                {:state => "decommissioning", :agent_identity => "1", :from_state => "booting"},
                                nil,
                                Proc]
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        RightScale::InstanceState.last_recorded_value.should == "booting"
        @sender.should_receive(:send_retryable_request).with(*@operational_args).once
        @sender.should_receive(:send_retryable_request).with(*decommissioning_args).and_yield(@record_success).once
        RightScale::InstanceState.value = "operational"
        RightScale::InstanceState.record_request.should_not be_nil
        flexmock(RightScale::InstanceState.record_request).should_receive(:cancel).with("re-request").once
        RightScale::InstanceState.value = "decommissioning"
        RightScale::InstanceState.value.should == "decommissioning"
        RightScale::InstanceState.last_recorded_value.should == "decommissioning"
        EM.stop
      end
    end

    it 'should raise an exception if the value being set is invalid' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        lambda do
          RightScale::InstanceState.value = "stopped"
        end.should raise_error(RightScale::Exceptions::Argument)
        EM.stop
      end
    end

    it 'should raise an exception if in read-only mode' do
      run_em_test do
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.init(@identity, read_only = true)
        lambda do
          RightScale::InstanceState.value = "stopped"
        end.should raise_error(RightScale::Exceptions::Application)
        EM.stop
      end
    end

  end

  context :shutdown do

    it 'should record decommissioned state without specifying last recorded state' do
      run_em_test do
        flexmock(EM).should_receive(:add_timer).times(3)
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        RightScale::InstanceState.value = "decommissioning"
        @sender.should_receive(:send_retryable_request).with(*@decommissioned_args).once
        RightScale::InstanceState.shutdown(@user_id, false, 'terminate')
        EM.stop
      end
    end

    it 'should request removal of queue' do
      run_em_test do
        now = Time.at(1000000)
        flexmock(Time).should_receive(:now).and_return(now)
        flexmock(EM).should_receive(:add_timer).times(3)
        RightScale::InstanceState.init(@identity)
        RightScale::InstanceState.value.should == "booting"
        RightScale::InstanceState.value = "decommissioning"
        @sender.should_receive(:send_push).with('/registrar/remove', {:agent_identity => '1', :created_at => now.to_i}).once
        RightScale::InstanceState.shutdown(@user_id, false, 'terminate')
        EM.stop
      end
    end

  end

  it 'should update last communication and store it but only if sufficient time has elapsed' do
    run_em_test do
      RightScale::InstanceState.init(@identity)
      flexmock(RightScale::InstanceState).should_receive(:store_state).once
      RightScale::InstanceState.message_received
      RightScale::InstanceState.message_received
      EM.stop
    end
  end

  it 'should always record startup tags' do
    run_em_test do
      RightScale::InstanceState.init(@identity)
      RightScale::InstanceState.startup_tags = [ 'a_tag', 'another_tag' ]
      RightScale::InstanceState.init(@identity)
      RightScale::InstanceState.startup_tags.should == [ 'a_tag', 'another_tag' ]
      EM.stop
    end
  end

end
