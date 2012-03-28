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

describe RightScale::PolicyManager do
  let(:policy_name) {'foo'}
  let(:bundle_nil_policy) {flexmock('bundle', :runlist_policy => nil) }
  let(:bundle) {flexmock('bundle', :runlist_policy => flexmock('rlp', :policy_name => policy_name)) }

  before(:each) do
    flexmock(RightScale::AuditProxy).should_receive(:create).and_return(flexmock('audit', :audit_id => rand**32))
    RightScale::PolicyManager.reset
  end
  
  context :success do
    context 'when the given bundle is nil' do
      it 'should return false' do
        RightScale::PolicyManager.success(nil).should be_false
      end
    end

    context 'when the given bundle has a nil runlist policy' do
      it 'should return false' do
        RightScale::PolicyManager.success(bundle_nil_policy).should be_false
      end
    end

    context 'when the given bundle refers to an unknown policy' do
      it 'should return true' do
        RightScale::PolicyManager.success(bundle).should be_true
      end
      it 'should register the unknown policy' do
        RightScale::PolicyManager.success(bundle)
        RightScale::PolicyManager.policy[@policy_name].should_not be_nil
      end
    end

    context 'when the given bundle refers to an known policy' do
      it 'should return true' do
        RightScale::PolicyManager.success(@bundle).should == true
      end
      it 'should increment the policy success count' do
        RightScale::PolicyManager.success(@bundle)
        RightScale::PolicyManager.get_policy(@policy_name).count.should == 1
      end

      it 'should increment the policy success count when success called many times' do
        RightScale::PolicyManager.success(@bundle)
        RightScale::PolicyManager.success(@bundle)
        RightScale::PolicyManager.success(@bundle)
        RightScale::PolicyManager.get_policy(@bundle).count.should == 3
      end
    end
  end
  
  context :fail do
    context 'when the given bundle is nil' do
      it 'should return false' do
        RightScale::PolicyManager.fail(nil).should be_false
      end
    end

    context 'when the given bundle has a nil runlist policy' do
      it 'should return false' do
        RightScale::PolicyManager.fail(bundle_nil_policy).should be_false
      end
    end

    context 'when the given bundle refers to an unknown policy' do
      it 'should return true' do
        RightScale::PolicyManager.fail(bundle).should be_true
      end
      it 'should register the unknown policy' do
        RightScale::PolicyManager.fail(bundle)
        RightScale::PolicyManager.policy[@policy_name].should_not be_nil
      end
    end

    context 'when the given bundle refers to an known policy' do
      it 'should return true' do
        RightScale::PolicyManager.fail(@bundle).should == true
      end
      it 'should reset the policy success count' do
        RightScale::PolicyManager.success(@bundle)
        RightScale::PolicyManager.success(@bundle)
        RightScale::PolicyManager.get_policy(@bundle).count.should == 2
        RightScale::PolicyManager.fail(@bundle)
        RightScale::PolicyManager.get_policy(@bundle).count.should == 0
      end
    end
  end
  
  context :get_audit do
    context 'when the given bundle is nil' do
      it 'should return nil' do
        RightScale::PolicyManager.get_audit(@bundle).should be_nil
      end
    end

    context 'when the given bundle has a nil runlist policy' do
      it 'should return nil' do
        RightScale::PolicyManager.get_audit(bundle_nil_policy).should be_nil
      end
    end

    context 'when the given bundle refers to an unknown policy' do
      it 'should return a new audit' do
        RightScale::PolicyManager.policy[@policy_name].should be_nil
        audit = RightScale::PolicyManager.get_audit(@bundle)
        RightScale::PolicyManager.get_policy(@bundle).audit.should === audit
      end
    end

    context 'when the given bundle refers to an known policy' do
      it 'should return a new audit' do
        policy = RightScale::PolicyManager.get_policy(@bundle)
        RightScale::PolicyManager.get_audit(@bundle).should === policy.audit
      end
    end
  end

  context :get_policy do
    context 'when the given bundle is nil' do
      it 'should return nil' do
        RightScale::PolicyManager.get_policy(nil).should be_nil
      end
    end

    context 'when the given bundle has a nil runlist policy' do
      it 'should return nil' do
        RightScale::PolicyManager.get_policy(bundle_nil_policy).should be_nil
      end
    end

    context 'when the given bundle refers to an unknown policy' do
      it 'should return create a new policy' do
        RightScale::PolicyManager.policy[@policy_name].should be_nil
        policy = RightScale::PolicyManager.get_policy(bundle)
        policy.should_not be_nil
        RightScale::PolicyManager.policy[@policy_name].should === policy
      end
    end

    context 'when the given bundle refers to an known policy' do
      it 'should return create a new policy' do
        policy = RightScale::PolicyManager.get_policy(bundle)
        RightScale::PolicyManager.get_policy(bundle).should === policy
      end
    end
  end
  
end