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

require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'login_manager'
require 'agent_tags_manager'
require 'right_link_log'

describe RightScale::LoginManager do
  include RightScale::SpecHelpers

  before(:all) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).by_default
    @mgr = RightScale::LoginManager.instance
    flexmock(@mgr).should_receive(:supported_by_platform?).and_return(true).by_default
    flexmock(@mgr).should_receive(:write_keys_file).and_return(true).by_default
  end

  context :update_policy do
    before(:each) do
      flexmock(RightScale::InstanceState).should_receive(:login_policy).and_return(nil).by_default
      flexmock(RightScale::InstanceState).should_receive(:login_policy=).by_default
      flexmock(RightScale::AgentTagsManager).should_receive("instance.add_tags")
      flexmock(@mgr).should_receive(:schedule_expiry)
      
      @system_keys = [ "ssh-rsa #{rand(3**32).to_s(32)} someone@localhost",
                       "ssh-dsa #{rand(3**32).to_s(32)} root@localhost" ]

      @policy = RightScale::LoginPolicy.new(1234, 1.hours.ago)
      @policy_keys = []
      (0...3).each do |i|
        num = rand(2**32).to_s(32)
        pub = rand(2**32).to_s(32)
        @policy.users << RightScale::LoginUser.new("v0-#{num}", "rs-#{num}", "ssh-rsa #{pub} #{num}@rightscale.com", "#{num}@rightscale.com", true, nil)
        @policy_keys  << "ssh-rsa #{pub} #{num}@rightscale.com" 
      end
    end

    it "should only add non-expired users" do
      @policy.users[0].expires_at = 1.days.ago
      flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys[1..2]).sort)
      @mgr.update_policy(@policy)
    end
    
    it "should only add users with superuser privilege" do
      @policy.users[0].superuser = false
      flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys[1..2]).sort)
      @mgr.update_policy(@policy)
    end
    
    context "when system keys exist" do
      it "should cope with malformed system keys" do
        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys + ['hello world', 'four score and seven years ago'])
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort)
        @mgr.update_policy(@policy)
      end

      it "should preserve the system keys and add the policy keys" do
        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys)
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort)
        @mgr.update_policy(@policy)
      end

      context "and a previous policy exists" do
        before(:each) do
          @old_policy_users = []
          @old_policy_keys  = []
          (0...3).each do |i|
            num = rand(2**32).to_s(32)
            pub = rand(2**32).to_s(32)
            @old_policy_users << RightScale::LoginUser.new("v0-#{num}", "rs-#{num}", "ssh-rsa #{pub} #{num}@rightscale.old", "#{num}@rightscale.old", true, nil)
            @old_policy_keys  << "ssh-rsa #{pub} #{num}@rightscale.old" 
          end
          @old_policy = RightScale::LoginPolicy.new(1234)
          @old_policy.users = @old_policy_users
          flexmock(RightScale::InstanceState).should_receive(:login_policy).and_return(@old_policy)
        end

        it "should preserve the system keys but remove the old policy keys" do
          flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys + @old_policy_keys)
          flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort)
          @mgr.update_policy(@policy)
        end
      end

      context "and the new policy is exclusive" do
        before(:each) { @policy.exclusive = true }
        
        it "should remove the system keys and add the policy keys" do
          flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys)
          flexmock(@mgr).should_receive(:write_keys_file).with(@policy_keys.sort)
          @mgr.update_policy(@policy)
        end
      end
    end
  end

  context :schedule_expiry do
    before(:each) do
      @policy = RightScale::LoginPolicy.new(1234, 1.hours.ago)
      @policy_keys = []
    end

    context 'when no users are set to expire' do
      before(:each) do
        u1 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, nil)
        u2 = RightScale::LoginUser.new("v0-2345", "rs2345", "ssh-rsa bbb 2345@rightscale.com", "2345@rightscale.com", true, nil) 
        @policy.users << u1
        @policy.users << u2
      end

      it 'should not create a timer' do
        flexmock(EventMachine::Timer).should_receive(:new).never
        policy = @policy
        @mgr.instance_eval {
          schedule_expiry(policy).should == false
        }
      end
    end

    context 'when a user will expire in 1 hour' do
      before(:each) do
        u1 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, 1.hours.from_now)
        u2 = RightScale::LoginUser.new("v0-2345", "rs2345", "ssh-rsa bbb 2345@rightscale.com", "2345@rightscale.com", true, nil)
        @policy.users << u1
        @policy.users << u2
      end

      it 'should create a timer for 1 hour' do
        flexmock(EventMachine::Timer).should_receive(:new).with(1.hours+1, Proc)
        policy = @policy
        @mgr.instance_eval {
          schedule_expiry(policy).should == true
        }
      end

      context 'and a user will expire in 15 minutes' do
        before(:each) do
          u3 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, 15.minutes.from_now)
          @policy.users << u3
        end

        it 'should create a timer for 15 minutes' do
          flexmock(EventMachine::Timer).should_receive(:new).with(15.minutes+1, Proc)
          policy = @policy
          @mgr.instance_eval {
            schedule_expiry(policy).should == true
          }
        end
      end
    end
  end
end
