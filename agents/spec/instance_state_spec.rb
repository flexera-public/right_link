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
 
  before(:all) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
    setup_state
  end

  after(:all) do
    cleanup_state
  end

  it 'should initialize' do
    RightScale::InstanceState.value.should == 'booting'
    RightScale::InstanceState.identity.should == @identity
  end 

  context :init do
    before(:each) do
      flexmock(RightScale::RightLinkLog).should_receive(:debug).by_default
    end

    it 'should detect first run' do
      flexmock(File).should_receive(:file?).with(RightScale::InstanceState::STATE_FILE).and_return(false)
      flexmock(File).should_receive(:file?).with(RightScale::InstanceState::SCRIPTS_FILE).and_return(false)
      flexmock(File).should_receive(:file?).with(RightScale::InstanceState::LOGIN_POLICY_FILE).and_return(false)

      RightScale::InstanceState.init(@identity)

      RightScale::InstanceState.value.should == 'booting'
    end

    context('when saved state exists') do
      before(:each) do
        @first_booted_at = Time.at(Time.now.to_i - 5*60).to_i
        #Simulate a successful first boot
        saved_state = {'value' => 'operational', 'identity' => '1',
                       'uptime' => 120.0, 'booted_at' => @first_booted_at,
                       'startup_tags' => []}
        flexmock(RightScale::InstanceState).should_receive(:read_json).with(RightScale::InstanceState::STATE_FILE).and_return(saved_state).by_default        
      end

      it 'should detect restart after decommission' do
        #Simulate a prior decommission
        saved_state = {'value' => 'decommissioned', 'identity' => '1',
                       'uptime' => 120.0, 'booted_at' => @first_booted_at,
                       'startup_tags' => []}
        flexmock(RightScale::InstanceState).should_receive(:read_json).with(RightScale::InstanceState::STATE_FILE).and_return(saved_state)
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(300.0)
        flexmock(RightScale::InstanceState).should_receive(:booted_at).and_return(@first_booted_at)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(RightScale::InstanceState::STATE_FILE, Hash).never
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(RightScale::InstanceState::SCRIPTS_FILE, Array).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).never

        RightScale::InstanceState.init(@identity)

        RightScale::InstanceState.value.should == 'decommissioned'
      end

      it 'should detect reboot' do
        @rebooted_at = @first_booted_at + 300
        flexmock(RightScale::InstanceState).should_receive(:uptime).and_return(1.0)
        flexmock(RightScale::InstanceState).should_receive(:booted_at).and_return(@rebooted_at)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(RightScale::InstanceState::STATE_FILE, Hash)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(RightScale::InstanceState::SCRIPTS_FILE, Array).never
        flexmock(RightScale::InstanceState).should_receive(:record_state).with('booting')

        RightScale::InstanceState.init(@identity)

        RightScale::InstanceState.identity.should == '1'
        RightScale::InstanceState.value.should == 'booting'
      end

      it 'should detect bundled boot' do
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(RightScale::InstanceState::STATE_FILE, Hash)
        flexmock(RightScale::InstanceState).should_receive(:write_json).with(RightScale::InstanceState::SCRIPTS_FILE, [])
        flexmock(RightScale::InstanceState).should_receive(:record_state).with('booting')

        RightScale::InstanceState.init('2')

        RightScale::InstanceState.identity.should == '2'
        RightScale::InstanceState.value.should == 'booting'
      end
    end
  end

  it 'should record script execution' do
    RightScale::InstanceState.past_scripts.should be_empty
    RightScale::InstanceState.record_script_execution('test')
    RightScale::InstanceState.past_scripts.should == [ 'test' ]
  end

  it 'should record startup tags when transitioning from booting' do
    flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
            with('/state_recorder/record', { :state => "booting", :agent_identity => "1" }, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.init(@identity)
    flexmock(RightScale::RequestForwarder.instance).should_receive(:request).
            with('/state_recorder/record', { :state => "operational", :agent_identity => "1" }, Proc).
            and_yield(@results_factory.success_results)
    RightScale::InstanceState.startup_tags = [ 'a_tag', 'another_tag' ]
    RightScale::InstanceState.value = 'operational'
    RightScale::InstanceState.startup_tags = nil
    RightScale::InstanceState.init(@identity)
    RightScale::InstanceState.startup_tags.should == [ 'a_tag', 'another_tag' ]
  end

end
