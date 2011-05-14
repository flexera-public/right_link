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

describe RightScale::LoginManager do
  include RightScale::SpecHelpers

  # equivalent of x.minutes for dev setup without activesupport
  def minutes(count)
    return count * 60
  end

  #given a scalar value, return a range encompassing that value plus or minus
  #n (where n = 3 by default)
  def approximately(t, n=3)
    return (t-n)..(t+n)
  end

  # equivalent of x.minutes.from_now for dev setup without activesupport
  def minutes_from_now(count)
    return Time.now + minutes(count)
  end

  # equivalent of 1.hours for dev setup without activesupport
  def one_hour
    return 60 * 60
  end

  # equivalent of 3.months for dev setup without activesupport
  def three_months
    return 60 * 60 * 24 * 90
  end

  # equivalent of 1.hours.from_now for dev setup without activesupport
  def one_hour_from_now
    return Time.now + one_hour
  end

  def three_months_from_now
    return Time.now + three_months
  end

  # equivalent of 1.hours.ago for dev setup without activesupport
  def one_hour_ago
    return Time.now - one_hour
  end

  # equivalent of 1.days.ago for dev setup without activesupport
  def one_day_ago
    return Time.now - 24 * one_hour
  end

  before(:each) do
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

      @policy = RightScale::LoginPolicy.new(1234, one_hour_ago)
      @policy_keys = []
      (0...3).each do |i|
        num = rand(2**32).to_s(32)
        pub = rand(2**32).to_s(32)
        public_keys = ["ssh-rsa #{pub} #{num}@rightscale.com"]

        # add a second public key for user #1
        if 1 == i
          pub = rand(2**32).to_s(32)
          public_keys << "ssh-rsa #{pub} #{num}@rightscale.com"
        end
        @policy.users << RightScale::LoginUser.new("v0-#{num}", "rs-#{num}", nil, "#{num}@rightscale.com", true, nil, public_keys)
        public_keys.each { |public_key| @policy_keys << public_key }
      end
    end

    it "should only add non-expired users" do
      @policy.users[0].expires_at = one_day_ago
      flexmock(@mgr).should_receive(:read_keys_file).and_return([])
      flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys[1..3]).sort).and_return(true)
      @mgr.update_policy(@policy)
    end
    
    it "should only add users with superuser privilege" do
      @policy.users[0].superuser = false
      flexmock(@mgr).should_receive(:read_keys_file).and_return([])
      flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys[1..3]).sort).and_return(true)
      @mgr.update_policy(@policy)
    end
    
    context "when system keys exist" do
      it "should discard malformed system keys" do
        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys + ['hello world', 'four score and seven years ago'])
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort).and_return(true)
        @mgr.update_policy(@policy)
      end

      it "should ignore comments" do
        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys + ['#i like traffic lights', '    #ice cream is good'])
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort).and_return(true)
        flexmock(RightScale::RightLinkLog).should_receive(:error).never
        @mgr.update_policy(@policy)
      end

      it "should preserve system keys with an options field (without preserving options)" do
        @stripped_keys = @system_keys.dup
        fake_pub_material = rand(3**32).to_s(32) 
        @system_keys << "joebob=\"xyz wqr\",friendly=false ssh-rsa #{fake_pub_material} Hey, This is my Key!"
        @stripped_keys << "ssh-rsa #{fake_pub_material} Hey, This is my Key!"

        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys)
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@stripped_keys).sort).and_return(true)
        @mgr.update_policy(@policy)
      end

      it "should preserve system keys with spaces in the comment" do
        @system_keys << "ssh-rsa #{rand(3**32).to_s(32)} Hey, This is my Key!"
        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys)
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort).and_return(true)
        @mgr.update_policy(@policy)
      end

      it "should preserve the system keys and add the policy keys" do
        flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys)
        flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort).and_return(true)
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
          flexmock(@mgr).should_receive(:write_keys_file).with((@policy_keys+@system_keys).sort).and_return(true)
          @mgr.update_policy(@policy)
        end
      end

      context "and the new policy is exclusive" do
        before(:each) { @policy.exclusive = true }
        
        it "should remove the system keys and add the policy keys" do
          flexmock(@mgr).should_receive(:read_keys_file).and_return(@system_keys)
          flexmock(@mgr).should_receive(:write_keys_file).with(@policy_keys.sort).and_return(true)
          @mgr.update_policy(@policy)
        end
      end
    end
  end

  context :schedule_expiry do
    before(:each) do
      @policy = RightScale::LoginPolicy.new(1234, one_hour_ago)
      @policy_keys = []
    end

    context 'when no users are set to expire' do
      before(:each) do
        u1 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, nil)
        u2 = RightScale::LoginUser.new("v0-2345", "rs2345", nil, "2345@rightscale.com", true, nil, ["ssh-rsa bbb 2345@rightscale.com"])
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

    context 'when a user will expire in 90 days' do
      before(:each) do
        u1 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, three_months_from_now)
        u2 = RightScale::LoginUser.new("v0-2345", "rs2345", "ssh-rsa bbb 2345@rightscale.com", "2345@rightscale.com", true, nil)
        @policy.users << u1
        @policy.users << u2
      end


      it 'should create a timer for 1 day' do
        flexmock(EventMachine::Timer).should_receive(:new).with(approximately(86_400), Proc)
        policy = @policy
        @mgr.instance_eval {
          schedule_expiry(policy).should == true
        }
      end
    end

    context 'when a user will expire in 1 hour' do
      before(:each) do
        u1 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, one_hour_from_now)
        u2 = RightScale::LoginUser.new("v0-2345", "rs2345", "ssh-rsa bbb 2345@rightscale.com", "2345@rightscale.com", true, nil)
        @policy.users << u1
        @policy.users << u2
      end

      it 'should create a timer for 1 hour' do
        flexmock(EventMachine::Timer).should_receive(:new).with(approximately(one_hour), Proc)
        policy = @policy
        @mgr.instance_eval {
          schedule_expiry(policy).should == true
        }
      end

      context 'and a user will expire in 15 minutes' do
        before(:each) do
          u3 = RightScale::LoginUser.new("v0-1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, minutes_from_now(15))
          @policy.users << u3
        end

        it 'should create a timer for 15 minutes' do
          flexmock(EventMachine::Timer).should_receive(:new).with(approximately(minutes(15)), Proc)
          policy = @policy
          @mgr.instance_eval {
            schedule_expiry(policy).should == true
          }
        end
      end
    end
  end
end
