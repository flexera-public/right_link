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

  # Manages policies
  class PolicyManager
    class << self
      attr_reader :policy
    end

    # Policy hash keyed by policy name
    @policy = Hash.new

    # Signals the successful execution of a right script or recipe with the given bundle
    #
    # === Parameters
    # bundle(ExecutableBundle):: bundle containing a RunlistPolicy
    #
    # === Return
    # result(Boolean):: Return false if the bundle fails to provide a valid runlist policy
    def self.success(bundle)
      policy = self.get_policy_from_bundle(bundle)
      return false unless policy

      policy.count = policy.count + 1
      timestamp = Time.now
      if timestamp - policy.audit_timestamp >= policy.audit_period
        policy.audit.audit.append_info("Policy #{policy.name} has successfully run #{policy.count} times in the last #{policy.audit_period} seconds")
        policy.audit_timestamp = timestamp
      end
      true
    end

    # Signals the failed execution of a recipe with the given bundle
    #
    # === Parameters
    # bundle(ExecutableBundle):: bundle containing a RunlistPolicy
    #
    # === Return
    # result(Boolean):: Return false if the bundle fails to provide a valid runlist policy
    def self.fail(bundle)
      policy = self.get_policy_from_bundle(bundle)
      return false unless policy
      policy.count = 0
      true
    end

    # Returns the audit for the given policy of the bundle
    #
    # === Parameters
    # bundle(ExecutableBundle):: An executable bundle
    #
    # === Return
    # result(PolicyAudit):: a PolicyAudit instance that wraps AuditProxy
    def self.get_audit(bundle)
      policy = self.get_policy_from_bundle(bundle)
      policy ? policy.audit : nil
    end

    def self.reset
       @policy.clear
    end

    private

    # Returns the policy that matches the bundle or creates a new one
    #
    # === Parameters
    # bundle(ExecutableBundle):: An executable bundle
    #
    # === Return
    # result(Policy):: Policy based on the bundle's RunlistPolicy or nil
    def self.get_policy_from_bundle(bundle)
      runlist_policy = bundle.runlist_policy if bundle.respond_to?(:runlist_policy)
      policy = nil
      if runlist_policy && runlist_policy.policy_name
        @policy[runlist_policy.policy_name] ||= Policy.new(runlist_policy.policy_name, runlist_policy.audit_period)
        policy = @policy[runlist_policy.policy_name]
      end
      policy
    end

  end

end