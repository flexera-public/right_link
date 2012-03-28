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

module RightScale

  # Manages policies
  class PolicyManager
    # Hash of policy classes keyed by policy name
    @policy = Hash.new
    
    # Signals the successful execution of a recipe with the given policy name
    #
    # === Parameters
    # policy_name(String):: name of the policy
    #
    # === Return
    # true:: Always return true
    def self.success(policy_name)
      policy = self.get_policy(policy_name)
      policy.count = policy.count + 1
      true
    end
    
    # Signals the failed execution of a recipe with the given policy name
    #
    # === Parameters
    # policy_name(String):: name of the policy
    #
    # === Return
    # true:: Always return true
    def self.fail(policy_name)
      self.get_policy(policy_name).count = 0
      true
    end

    def self.get_audit(bundle)

    end

    def self.reset
      @policy.clear
    end
    private

    # Accessor method for policy hash
    def self.policy
      @policy
    end

    # === Parameters
    # bundle(ExecutableBundle):: An executable bundle
    #
    # === Return
    # result(String):: Policy name of this bundle
    def get_policy_name_from_bundle(bundle)
      policy_name = nil
      policy_name ||= bundle.runlist_policy.policy_name if bundle.respond_to?(:runlist_policy) && bundle.runlist_policy
      policy_name
    end

    # Returns the audit ID associated with the given policy
    #
    # === Parameters
    # policy_name(String):: name of the policy
    #
    # === Return
    # result(Integer):: Audit ID associated with this policy
    def self.audit_id_for(policy_name)
      self.get_policy(policy_name).audit_id
    end
    
    # Returns the timestamp of the last audit of a recipe with the given policy name
    #
    # === Parameters
    # policy_name(String):: name of the policy
    #
    # === Return
    # result(Integer):: UNIX Timestamp
    def self.last_audit_for(policy_name)
      self.get_policy(policy_name).audit_timestamp
    end
    
    # Returns the number of successful runs of the recipe with the given policy name since the last time it audited
    #
    # === Parameters
    # policy_name(String):: name of the policy
    #
    # === Return
    # result(Integer):: UNIX Timestamp
    def self.success_count_for(policy_name)
      self.get_policy(policy_name).count
    end
    
    # Returns the policy associated with the given policy name
    #
    # === Parameters
    # policy_name(String):: name of the policy
    #
    # === Return
    # result(Policy):: Policy object
    def self.get_policy(policy_name)
      policy = self.policy[policy_name] ||= Policy.new(policy_name)
      unless policy.audit_id
        RightScale::AuditProxy.create(InstanceState.identity, policy.name) do |audit|
          policy.audit_id = audit.audit_id
        end
      end
      policy
    end
    
  end

end