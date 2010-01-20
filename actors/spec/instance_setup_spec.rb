require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'right_popen'  # now an installed gem
require File.join(File.dirname(__FILE__), 'auditor_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')
require 'instance_lib'
require 'instance_setup'

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
  def request(operation, *args)
    case operation
      when "/booter/set_r_s_version" then yield @@factory.success_results
      when "/booter/get_repositories" then yield @@repos
      when "/booter/get_boot_bundle" then yield @@bundle
      when "/booter/get_login_policy" then yield @@login_policy
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
    @auditor = RightScale::AuditorProxyMock.new
    flexmock(RightScale::AuditorProxy).should_receive(:new).and_return(@auditor)
    @results_factory = RightScale::NaniteResultsMock.new
    InstanceSetup.results_factory = @results_factory
    @mgr = RightScale::LoginManager.instance
    flexmock(@mgr).should_receive(:supported_by_platform?).and_return(true)
    flexmock(@mgr).should_receive(:write_keys_file).and_return(true)
    setup_state
    setup_script_execution
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
    InstanceSetup.repos        = repos
    InstanceSetup.bundle       = bundle

    EM.run do
      @setup.__send__(:initialize, @agent_identity.to_s)
      EM.add_periodic_timer(0.1) { check_state }
      EM.add_timer(100) { EM.stop }
    end
  end

  it 'should boot' do
    policy = RightScale::InstantiationMock.login_policy 
    repos  = RightScale::InstantiationMock.repositories
    bundle = RightScale::InstantiationMock.script_bundle('__TestScripts', '__TestScripts_too')
    boot(policy, repos, bundle)
    res = @setup.report_state
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
