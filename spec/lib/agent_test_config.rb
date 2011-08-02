# Test instance agent configuration files location
# This is used by both the (mock) instance agent and the integration test runner
class AgentTestConfig

  def self.state_file(agent_identity)
    return local_file(agent_identity, '__state.js')
  end

  def self.scripts_file(agent_identity)
    return local_file(agent_identity, '__past_scripts.js')
  end

  def self.login_policy_file(agent_identity)
    return local_file(agent_identity, '__login_policy.js')
  end

  def self.cache_dir(agent_identity)
    return local_file(agent_identity, '__cache')
  end

  def self.boot_log_file(agent_identity)
    return local_file(agent_identity, '__boot.log')
  end

  def self.operation_log_file(agent_identity)
    return local_file(agent_identity, '__operation.log')
  end

  def self.decommission_log_file(agent_identity)
    return local_file(agent_identity, '__decommission.log')
  end

  def self.chef_file(agent_identity)
    return local_file(agent_identity, '__chef.js')
  end

  def self.cook_state_file
    return local_file('', '__cook_state.js')
  end

  def self.agent_identity_file
    return local_file('', '__agent_identity')
  end

  private

  def self.local_file(agent_identity, suffix)
    # windows cannot execute powershell scripts cached on a shared network
    # drive without user intervention, so a problem arises when running spec
    # tests from a shared source folder. the quick and dirty solution is to
    # always use the temp directory in testing.
    base_dir = File.join(RightScale::Platform.filesystem.temp_dir, "right_net_spec")
    return File.join(base_dir, "#{agent_identity}#{suffix}")
  end

end
