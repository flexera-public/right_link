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

# Test agent configuration files location
# This is moreless duplicated in right_api for right_net integration testing
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
    # Windows cannot execute powershell scripts cached on a shared network
    # drive without user intervention, so a problem arises when running spec
    # tests from a shared source folder. The quick and dirty solution is to
    # always use the temp directory in testing.
    base_dir = File.join(RightScale::Platform.filesystem.temp_dir, "right_link_spec")
    return File.join(base_dir, "#{agent_identity}#{suffix}")
  end

end
