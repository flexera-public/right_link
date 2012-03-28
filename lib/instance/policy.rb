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

module RightScale

  class Policy
    attr_accessor :policy_name, :audit_period, :audit, :count, :audit_timestamp
    
    def initialize(policy_name, audit_period)
      @policy_name  = policy_name
      @audit_period = audit_period
      @count = 0

      RightScale::AuditProxy.create(RightScale::InstanceState.identity, "Policy #{policy_name}") do |audit|
        @audit = RightScale::PolicyAudit.new(audit)
        audit.append_info("First run of reconvergence Policy: '#{policy_name}'")
        @audit_timestamp = Time.now
      end
    end
  end
  
end