#
# Copyright (c) 2009 RightScale Inc
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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.join(File.dirname(__FILE__), '..', 'lib', 'instance_setup')
require File.join(File.dirname(__FILE__), 'audit_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')
require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'results_mock')
require 'right_popen'

# We can't mock the different calls to request properly
# rake spec seems to always return the last match
# We can't provide an implementation as a block because we need to
# yield. So monkey patch to the rescue.
class InstanceSetup
  def self.results_factory=(factory)
    @@factory = factory
  end
  def self.repos=(repos)
    @@repos = repos
  end
  def self.bundle=(bundle)
    @@bundle = bundle
  end
  def self.login_policy=(login_policy)
    @@login_policy = login_policy
  end
  def self.agents=(agents)
    @@agents = agents
  end
  def send_retryable_request(operation, *args)
    case operation
    when "/booter/set_r_s_version" then yield @@factory.success_results
    when "/booter/get_repositories" then yield @@repos
    when "/booter/get_boot_bundle" then yield @@bundle
    when "/booter/get_login_policy" then yield @@login_policy
    when "/mapper/list_agents" then yield @@agents
    when "/storage_valet/get_planned_volume_mappings" then yield success_result([])
    else raise ArgumentError.new("Don't know how to mock #{operation}")
    end
  end
  def send_persistent_request(operation, *args)
    case operation
    when "/booter/declare" then yield @@factory.success_results
    else raise ArgumentError.new("Don't know how to mock #{operation}")
    end
  end
end

describe InstanceSetup do

  include RightScale::SpecHelpers

  before(:each) do
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1)
    @setup = flexmock(InstanceSetup.allocate)
    @setup.should_receive(:configure_repositories).and_return(RightScale::OperationResult.success)
    tags_manager_mock = flexmock(RightScale::AgentTagsManager)
    tags_manager_mock.should_receive(:tags).and_yield []
    flexmock(RightScale::AgentTagsManager).should_receive(:instance).and_return(tags_manager_mock)
    @audit = RightScale::AuditProxyMock.new(1)
    flexmock(RightScale::AuditProxy).should_receive(:new).and_return(@audit)
    @results_factory = RightScale::ResultsMock.new
    InstanceSetup.results_factory = @results_factory
    @mgr = RightScale::LoginManager.instance
    flexmock(@mgr).should_receive(:supported_by_platform?).and_return(true)
    flexmock(@mgr).should_receive(:write_keys_file).and_return(true)
    status = flexmock('status', :success? => true)
    flexmock(RightScale).should_receive(:popen3).and_return { |o| o[:target].send(o[:exit_handler], status) }
    setup_state
    @mapper_proxy.should_receive(:initialize_offline_queue).and_yield

    # prevent Chef logging reaching the console during spec test.
    logger = flexmock(::RightScale::RightLinkLog.logger)
    logger.should_receive(:info).and_return(true)
    logger.should_receive(:error).and_return(true)
  end

  after(:each) do
    cleanup_state
    cleanup_script_execution
  end

  # Stop EM if setup reports a state of 'running' or 'stranded'
  def check_state
    EM.stop if @setup.report_state.content =~ /operational|stranded/
  end
 
  def boot(login_policy, repos, bundle = nil)
    login_policy = @results_factory.success_results(login_policy)
    repos        = @results_factory.success_results(repos)

    if bundle
      bundle = @results_factory.success_results(bundle)
    else
      bundle = @results_factory.error_results('Test')
    end

    InstanceSetup.login_policy = login_policy
    InstanceSetup.repos = repos
    InstanceSetup.bundle = bundle

    result = RightScale::OperationResult.success({ 'agent_id1' => { 'tags' => ['tag1'] } })
    agents = flexmock('result', :results => { 'mapper_id1' => result })
    InstanceSetup.agents = agents

    EM.run do
      @setup.__send__(:initialize, @agent_identity.to_s)
      EM.add_periodic_timer(0.1) { check_state }
      EM.add_timer(25) { EM.stop }
    end
  end

  it 'should boot' do
    policy = RightScale::InstantiationMock.login_policy 
    repos  = RightScale::InstantiationMock.repositories
    bundle = RightScale::InstantiationMock.script_bundle('__TestScripts', '__TestScripts_too')
    boot(policy, repos, bundle)
    res = @setup.report_state
    if !res.success? || res.content != 'operational'
      @audit.audits.each { |a| puts a[:text] }
    end
    res.should be_success
    res.content.should == 'operational'
  end

  it 'should strand' do
    boot(RightScale::InstantiationMock.login_policy, RightScale::InstantiationMock.repositories)
    res = @setup.report_state
    res.should be_success
    res.content.should == 'stranded'
  end

end
