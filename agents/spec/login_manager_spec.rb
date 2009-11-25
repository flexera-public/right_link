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
end
