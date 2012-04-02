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
    # Policy hash keyed by policy name
    @policies = Hash.new
    @registrations = Hash.new

    class << self
      attr_reader :policy

      def registered?(bundle)
        @policies.has_key?(policy_name_from_bundle(bundle))
      end

      # Registers the bundle with the Manager and calls the passed in block when registration completes
      # In a multithreaded environment, the
      #
      # === Parameters
      # bundle(ExecutableBundle):: bundle containing a RunlistPolicy
      # block(Block):: block to execute once registration is complete.  The block will be called with
      #
      # === Return
      # result(Boolean):: Return false if the bundle fails to provide a valid runlist policy
      def register(bundle, &block)
        runlist_policy = runlist_policy_from_bundle(bundle)
        if runlist_policy
          if registering?(runlist_policy.policy_name)
            # waiting for a new audit to be created, place the block to be called on the list of callbacks
            @registrations[runlist_policy.policy_name] << block if block
          else
            # this is the first registration, add the callback to the list of callbacks to be executed after the audit has been created
            @registrations[runlist_policy.policy_name] = (block) ? [block] : []
            # request a new audit
            RightScale::AuditProxy.create(RightScale::InstanceState.identity, "Reconvergence Policy '#{runlist_policy.policy_name}'") do |audit|
              policy = Policy.new(runlist_policy.policy_name, runlist_policy.audit_period, audit)
              @policies[policy.policy_name] = policy
              # drain the pending registrations
              @registrations[policy.policy_name].each { |blk| blk.call(bundle, policy.audit) }
              @registrations.delete(policy.policy_name)
            end
          end
          true
        end
        false
      end

      # Signals the successful execution of a right script or recipe with the given bundle
      #
      # === Parameters
      # bundle(ExecutableBundle):: bundle containing a RunlistPolicy
      #
      # === Return
      # result(Boolean):: Return false if the bundle fails to provide a valid runlist policy
      def success(bundle)
        policy = get_policy_from_bundle(bundle)
        return false unless policy
        policy.success
        true
      end

      # Signals the failed execution of a recipe with the given bundle
      #
      # === Parameters
      # bundle(ExecutableBundle):: bundle containing a RunlistPolicy
      #
      # === Return
      # result(Boolean):: Return false if the bundle fails to provide a valid runlist policy
      def fail(bundle)
        policy = get_policy_from_bundle(bundle)
        return false unless policy
        policy.fail
        true
      end

      # Returns the audit for the given policy of the bundle
      #
      # === Parameters
      # bundle(ExecutableBundle):: An executable bundle
      #
      # === Return
      # result(PolicyAudit):: a PolicyAudit instance that wraps AuditProxy
      def get_audit(bundle)
        policy = get_policy_from_bundle(bundle)
        policy ? policy.audit : nil
      end

      private

      # Returns the policy that matches the bundle or creates a new one
      #
      # === Parameters
      # bundle(ExecutableBundle):: An executable bundle
      #
      # === Return
      # result(Policy):: Policy based on the bundle's RunlistPolicy or nil
      def get_policy_from_bundle(bundle)
        @policies[policy_name_from_bundle(bundle)]
      end

      def registering?(policy_name)
        return @registrations.has_key?(policy_name)
      end

      def policy_name_from_bundle(bundle)
        runlist_policy = runlist_policy_from_bundle(bundle)
        if runlist_policy
          return runlist_policy.policy_name
        else
          return nil
        end
      end

      def runlist_policy_from_bundle(bundle)
        if bundle.respond_to?(:runlist_policy) && bundle.runlist_policy && bundle.runlist_policy.policy_name
          return bundle.runlist_policy
        else
          return nil
        end
      end
    end
  end

end