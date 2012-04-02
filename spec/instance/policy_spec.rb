#--
# Copyright (c) 2012 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale, Inc. and
# the licensee.
#++

require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::PolicyManager do
  let(:policy_name)             { 1234 }
  let(:audit_period)            { 24 }
  let(:audit)                   { flexmock('audit', :append_info => true) }

  context 'initialize' do
    it 'accepts policy_name as a string' do
      policy = RightScale::Policy.new(policy_name.to_s, audit_period, audit)
      policy.policy_name.should == policy_name.to_s
    end

    it 'converts policy_name to a string if it is not one' do
      policy = RightScale::Policy.new(policy_name, audit_period, audit)
      policy.policy_name.should == policy_name.to_s
    end

    it 'accepts audit_period as a string' do
      policy = RightScale::Policy.new(policy_name, audit_period.to_s, audit)
      policy.audit_period.should == audit_period
    end

    it 'converts policy_name to an integer if it is not one' do
      policy = RightScale::Policy.new(policy_name, audit_period, audit)
      policy.audit_period.should == audit_period.to_i
    end
  end
end