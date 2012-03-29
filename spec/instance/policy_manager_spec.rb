#
# Copyright (c) 2009-2012 RightScale Inc
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
#
require File.join(File.dirname(__FILE__), 'spec_helper')

Spec::Matchers.define :be_the_same_policy_as do |expected|
  match do |actual|
    expected.audit_id.should        == actual.audit_id
    expected.count.should           == actual.count
    expected.audit_timestamp.should == actual.audit_timestamp
  end
end

module RightScale
  class PolicyManager
    class << self
      def reset
        @policies.clear
      end
      def get_policy(bundle)
        get_policy_from_bundle(bundle)
      end
    end
  end
end

describe RightScale::PolicyManager do
  let(:policy_name)       {'foo'}
  let(:bundle_nil_policy) {flexmock('bundle', :runlist_policy => nil) }

  before(:each) do
    RightScale::PolicyManager.reset
  end

  context 'when the given bundle is nil' do
    it 'success should return false' do
      RightScale::PolicyManager.success(nil).should be_false
    end
    it 'fail should return false' do
      RightScale::PolicyManager.fail(nil).should be_false
    end
    it 'get_audit should return nil' do
      RightScale::PolicyManager.get_audit(nil).should be_nil
    end
  end

  context 'when the given bundle has a nil runlist policy' do
    it 'success should return false' do
      RightScale::PolicyManager.success(bundle_nil_policy).should be_false
    end
    it 'fail should return false' do
      RightScale::PolicyManager.fail(bundle_nil_policy).should be_false
    end
    it 'get_audit should return nil' do
      RightScale::PolicyManager.get_audit(bundle_nil_policy).should be_nil
    end
  end

  let(:bundle)      {flexmock('bundle', :audit_id => rand**32, :runlist_policy => flexmock('rlp', :policy_name => policy_name, :audit_period => 120)) }

  context 'when a policy has not been registered' do
    it 'success should return false' do
      RightScale::PolicyManager.success(bundle).should be_false
    end
    it 'fail should return false' do
      RightScale::PolicyManager.fail(bundle).should be_false
    end
    it 'get_audit should return nil' do
      RightScale::PolicyManager.get_audit(bundle).should be_nil
    end
  end

  context 'when a policy has been registered' do
    let(:audit_proxy) {flexmock('audit', :audit_id => rand**32)}

    before do
      audit_proxy.should_receive(:append_info).once.with("First run of reconvergence Policy: '#{policy_name}'")
      flexmock(RightScale::AuditProxy).should_receive(:create).and_yield(audit_proxy)
      RightScale::PolicyManager.register(bundle)
    end

    it 'get_audit should return the audit assigned to the existing policy' do
      RightScale::PolicyManager.get_audit(bundle).should_not be_nil
    end

    context :success do
      it 'should return true' do
        RightScale::PolicyManager.success(bundle).should be_true
      end

      it 'should increment the policy count' do
        RightScale::PolicyManager.success(bundle)
        RightScale::PolicyManager.success(bundle)
        RightScale::PolicyManager.success(bundle)
        RightScale::PolicyManager.get_policy(bundle).count.should == 3
      end

      context 'and the period since last audit has elapsed' do
        before do
          # ensure audit count is greater than one to start
          RightScale::PolicyManager.success(bundle)

          # sleep to ensure timestamps will not match
          sleep(0.1)

          # update the period so we dont have to wait so long
          existing_policy = RightScale::PolicyManager.get_policy(bundle)
          existing_policy.audit_period = Time.now - existing_policy.audit_timestamp

          # success is going to audit now
          audit_proxy.should_receive(:append_info).once.with(/Reconvergence policy '#{policy_name}' has successfully run .* times in the last .* seconds/)
        end

        it 'should update the last audit time stamp of the policy' do
          current_timestamp = RightScale::PolicyManager.get_policy(bundle).audit_timestamp
          RightScale::PolicyManager.success(bundle)
          RightScale::PolicyManager.get_policy(bundle).audit_timestamp.should > current_timestamp
        end

        it 'should reset the count' do
          RightScale::PolicyManager.get_policy(bundle).count.should == 1
          RightScale::PolicyManager.success(bundle)
          RightScale::PolicyManager.get_policy(bundle).count.should == 0
        end
      end

      context :fail do
        it 'should return true' do
          RightScale::PolicyManager.fail(bundle).should be_true
        end

        it 'should reset the count' do
          RightScale::PolicyManager.success(bundle)
          RightScale::PolicyManager.get_policy(bundle).count.should == 1
          RightScale::PolicyManager.fail(bundle)
          RightScale::PolicyManager.get_policy(bundle).count.should == 0
        end
      end
    end
  end
end