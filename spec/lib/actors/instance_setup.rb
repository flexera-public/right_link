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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'actors' 'instance_setup'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'executable_sequence_proxy'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'reenroll_manager'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook', 'cook_state')
require File.join(File.dirname(__FILE__), '..', 'agent_test_config')

class InstanceSetup

  # Mock repository configuration
  def configure_repositories(repositories)
    RightScale::OperationResult.success
  end

  def enable_managed_login
    boot
  end
end

module RightScale

  class << InstanceState
    # Force location of scripts cache, state and past script files so we can clean them up
    # Persist agent identity so that it can be retrieved by cook process and used to similarly force locations
    # in the monkey patched ExecutableSequence in test version of cook.rb
    alias :original_init :init
    def init(agent_identity, read_only = false)
      File.open(AgentTestConfig.agent_identity_file,"w"){|f|f.puts agent_identity}
      overrides = [ :STATE_FILE, :SCRIPTS_FILE, :BOOT_LOG_FILE, :OPERATION_LOG_FILE, :DECOMMISSION_LOG_FILE, :LOGIN_POLICY_FILE ]
      overrides.each { |c| InstanceState.const_set(c, AgentTestConfig.__send__(c.to_s.downcase.intern, agent_identity)) }
      AgentConfig.cache_dir = AgentTestConfig.cache_dir(agent_identity)
      FileUtils.mkdir_p(AgentConfig.cache_dir)
      AgentConfig.cloud_state_dir = AgentConfig.cache_dir
      original_init(agent_identity, read_only)
    end

    # Disable MOTD and wall updates about instance state
    alias :original_update_motd :update_motd
    def update_motd()
      true
    end
  end

	class << CookState

		alias :original_init :init
		def init
			CookState.const_set(:STATE_FILE, AgentTestConfig.cook_state_file)
			original_init
		end

	end

  class ExecutableSequenceProxy

    # Override path to cook script to use test script
    def cook_path
      return File.join(File.dirname(__FILE__), 'cook.rb')
    end

    def cook_path_and_arguments
      debug = ENV['DEBUG']
      if debug
        return "\"#{cook_path}\" --debugger #{debug}"
      else
        return "\"#{cook_path}\""
      end
    end

  end

  class ReenrollManager
    def self.set_reenrolling
      Log.info('[re-enroll] If this were a real instance, you would have triggered to reenroll.')
    end
  end
end
