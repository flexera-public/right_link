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
  
  before(:each) do
    @policy_name = "policy_name"
    mock_audit = flexmock('audit')
    mock_audit.should_receive(:audit_id).and_return(rand**32)
    flexmock(RightScale::AuditProxy).should_receive(:create).and_return(mock_audit)
  end
  
  context :success do
    it 'should increment the policy success count' do
      RightScale::PolicyManager.success(@policy_name)
      RightScale::PolicyManager.get_policy(@policy_name).count.should == 1
    end
    
    it 'should return true' do
      RightScale::PolicyManager.success(@policy_name).should == true
    end
    
  end
  
  context :fail do
    it 'should reset the policy success count' do
      RightScale::PolicyManager.get_policy(@policy_name).count = 1
      RightScale::PolicyManager.fail(@policy_name)
      RightScale::PolicyManager.get_policy(@policy_name).count.should == 0
    end
    
    it 'should return true' do
      RightScale::PolicyManager.success(@policy_name).should == true
    end
  end
  
  context :audit_id_for do
    it 'returns the audit ID for the policy' do
      audit_id = 1
      policy = RightScale::PolicyManager.get_policy(@policy_name)
      policy.audit_id = audit_id
      
      RightScale::PolicyManager.audit_id_for(@policy_name).should == audit_id
    end
  end
  
  context :last_audit_for do
    it 'returns the timestamp for the last audit for the policy' do
      audit_timestamp = Time.now
      policy = RightScale::PolicyManager.get_policy(@policy_name)
      policy.audit_timestamp = audit_timestamp
      
      RightScale::PolicyManager.last_audit_for(@policy_name).should == audit_timestamp
    end
  end
  
  context :success_count_for do
    it 'returns the success count for the policy' do
      count = 5
      policy = RightScale::PolicyManager.get_policy(@policy_name)
      policy.count = count
      
      RightScale::PolicyManager.success_count_for(@policy_name).should == count
    end
  end
  
  context :get_policy do
    it 'returns a new policy if one does not already exist' do
      policy_name = "policy_#{rand(5)}"
      expected_policy = RightScale::Policy.new(policy_name)
      actual_policy = RightScale::PolicyManager.get_policy(policy_name)
      
      actual_policy.should be_the_same_policy_as(expected_policy)
    end
    
    it 'returns a policy if one already exists' do
      expected_policy = RightScale::PolicyManager.get_policy(@policy_name)
      expected_policy.audit_id = 5
      actual_policy = RightScale::PolicyManager.get_policy(@policy_name)
      
      actual_policy.should be_the_same_policy_as(expected_policy)
    end
  end
  
end