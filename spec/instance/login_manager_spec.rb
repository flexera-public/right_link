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

describe RightScale::LoginManager do
  include RightScale::SpecHelper

  RIGHTSCALE_KEYS_FILE = '/home/rightscale/.ssh/authorized_keys'
  RIGHTSCALE_ACCOUNT_CREDS = {:user=>"rightscale", :group=>"rightscale"}

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

  # Generates a LoginUser with specified number of public keys
  def generate_user(public_keys_count, domain)
    num = rand(2**32-4097)
    public_keys = []

    public_keys_count.times do
      pub = rand(2**32).to_s(32)
      public_keys << "ssh-rsa #{pub} #{num}@#{domain}"
    end

    RightScale::LoginUser.new("#{num}", "user#{num}", nil, "#{num}@#{domain}", true, nil, public_keys)
  end

  before(:each) do
    flexmock(RightScale::Log).should_receive(:debug).by_default
    @mgr = RightScale::LoginManager.instance
  end

  describe "#supported_by_platform" do
    context "when platform is not Linux" do
      before(:each) do
        flexmock(RightScale::Platform).should_receive(:linux?).and_return(false)
      end

      it "returns false" do
        @mgr.supported_by_platform?.should be(false)
      end
    end

    context "when platform is Linux" do
      before(:each) do
        flexmock(RightScale::Platform).should_receive(:linux?).and_return(true)
        flexmock(RightScale::Platform).should_receive(:darwin?).and_return(false)
        flexmock(RightScale::Platform).should_receive(:windows?).and_return(false)
      end

      context 'and rightscale user exists' do
        before(:each) do
          flexmock(@mgr).should_receive(:user_exists?).with('rightscale').and_return(true)
        end

        it "returns true" do
          @mgr.supported_by_platform?.should be(true)
        end
      end

      context 'and rightscale user does not exist' do
        before(:each) do
          flexmock(@mgr).should_receive(:user_exists?).with('rightscale').and_return(false)
        end

        it "returns false" do
          @mgr.supported_by_platform?.should be(false)
        end
      end

    end
  end

  describe "#update_policy" do
    before(:each) do
      flexmock(@mgr).should_receive(:supported_by_platform?).and_return(true).by_default

      # === Mocks for OS specific operations
      flexmock(@mgr).should_receive(:write_keys_file).and_return(true).by_default
      flexmock(@mgr).should_receive(:add_user).and_return(nil).by_default
      flexmock(@mgr).should_receive(:manage_group).and_return(true).by_default
      flexmock(@mgr).should_receive(:user_exists?).and_return(false).by_default
      flexmock(@mgr).should_receive(:uid_exists?).and_return(false).by_default
      # === Mocks end

      flexmock(RightScale::InstanceState).should_receive(:login_policy).and_return(nil).by_default
      flexmock(RightScale::InstanceState).should_receive(:login_policy=).by_default
      flexmock(RightScale::AgentTagsManager).should_receive("instance.add_tags")
      flexmock(@mgr).should_receive(:schedule_expiry)

      @policy = RightScale::LoginPolicy.new(1234, one_hour_ago)
      @user_keys = []
      (0...3).each do |i|
        user = generate_user(i == 1 ? 2: 1, "rightscale.com")
        @policy.users << user
        user.public_keys.each do |key|
          @user_keys << "#{@mgr.get_key_prefix(user.username, user.common_name, user.uuid, user.superuser, "http://example.com/#{user.username}.tgz")} #{key}"
        end
      end
    end

    it "should not add authorized_keys for expired users" do
      @policy.users[0].expires_at = one_day_ago

      flexmock(@mgr).should_receive(:read_keys_file).and_return([])
      flexmock(@mgr).should_receive(:write_keys_file) do |keys, file, options|
        keys.length.should == (@policy.users.size - 1)
      end

      @mgr.update_policy(@policy)
    end
    
    it "should respect the superuser bit" do
      @policy.users[0].superuser = false
      flexmock(@mgr).should_receive(:read_keys_file).and_return([])
      flexmock(@mgr).should_receive(:manage_group).with('rightscale', :remove, @policy.users[0].username).ordered
      flexmock(@mgr).should_receive(:manage_group).with('rightscale', :add, @policy.users[1].username).ordered
      flexmock(@mgr).should_receive(:manage_group).with('rightscale', :add, @policy.users[2].username).ordered
      flexmock(@mgr).should_receive(:write_keys_file) do |keys, file, options|
        keys.length.should == @policy.users.size
      end
      @mgr.update_policy(@policy)
    end
  end

  describe "#schedule_expiry" do
    before(:each) do
      @policy = RightScale::LoginPolicy.new(1234, one_hour_ago)
      @superuser_keys = []
    end

    context 'when no users are set to expire' do
      before(:each) do
        u1 = RightScale::LoginUser.new("1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, nil)
        u2 = RightScale::LoginUser.new("2345", "rs2345", nil, "2345@rightscale.com", true, nil, ["ssh-rsa bbb 2345@rightscale.com"])
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
        u1 = RightScale::LoginUser.new("1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, three_months_from_now)
        u2 = RightScale::LoginUser.new("2345", "rs2345", "ssh-rsa bbb 2345@rightscale.com", "2345@rightscale.com", true, nil)
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
        u1 = RightScale::LoginUser.new("1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, one_hour_from_now)
        u2 = RightScale::LoginUser.new("2345", "rs2345", "ssh-rsa bbb 2345@rightscale.com", "2345@rightscale.com", true, nil)
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
          u3 = RightScale::LoginUser.new("1234", "rs1234", "ssh-rsa aaa 1234@rightscale.com", "1234@rightscale.com", true, minutes_from_now(15))
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
  
  describe "#modify_keys_to_use_individual_profiles" do
    before(:each) do
      public_key    = "ssh-rsa aaa 1234@rightscale.com"
      uid           = "1234"
      profile_data  = "test"
      @user         = RightScale::LoginUser.new(uid, "rs#{uid}", public_key, "#{uid}@rightscale.com", true, nil, [public_key], profile_data)
    end
    context "given profile data" do
      it 'should return a user\'s profile in the command string' do
        user = @user
        @mgr.instance_eval {
          keys = modify_keys_to_use_individual_profiles([user])
          keys.kind_of?(Array).should == true
          keys.size.should == 1
          keys.first.include?('--profile').should == true
        }
        
        # @User: #<RightScale::LoginUser:0x103622ad8 @common_name="1234@rightscale.com", @public_key="ssh-rsa aaa 1234@rightscale.com", @profile_data="test", @username="rs1234", @uuid="1234", @public_keys=["ssh-rsa aaa 1234@rightscale.com"], @superuser=true>
        # ["command=\"rs_thunk --username rs1234 --email 1234@rightscale.com --profile test\"  ssh-rsa aaa 1234@rightscale.com"]
      end
    end
  end
  
  describe "#get_key_prefix" do
    before(:each) do
      @username      = "123"
      @email         = "#{@username}@rightscale.com"
      @uuid          = @username.to_i
      @profile_data  = "test"
    end
    context "given username, email and uuid" do
      it "should return a rs_thunk command line with proper formatting" do
         key_prefix = @mgr.get_key_prefix(@username, @email, @uuid, false)
         key_prefix.should include('--username')
         key_prefix.should include('--email')
         key_prefix.should include('--uuid')
         key_prefix.should_not include('--superuser')
      end
    end
    context "given a superuser value of true" do
      it "should return a rs_thunk command line with proper formatting" do
        
        @mgr.get_key_prefix(@username, @email, @uuid, true).should include('--superuser')
      end
    end
    context "given a profile" do
      it "should return a rs_thunk command line with proper formatting" do
        
        @mgr.get_key_prefix(@username, @email, @uuid, false, @profile_data).should include('--profile')
      end
    end
  end
end
