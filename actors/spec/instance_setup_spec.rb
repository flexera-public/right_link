require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'right_popen', 'lib', 'right_popen')
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
  def request(operation, *args)
    case operation
      when "/booter/set_r_s_version" then yield @@factory.success_results
      when "/booter/get_repositories" then yield @@repos
      when "/booter/get_boot_bundle" then yield @@bundle
    end
  end
end

describe InstanceSetup do

  include RightScale::SpecHelpers

  before(:each) do
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1)
    @setup = InstanceSetup.allocate
    @setup.should_receive(:configure_repositories).and_return(RightScale::OperationResult.success)
    @auditor = RightScale::AuditorProxyMock.new
    RightScale::AuditorProxy.should_receive(:new).any_number_of_times.and_return(@auditor)
    @results_factory = RightScale::NaniteResultsMock.new
    InstanceSetup.results_factory = @results_factory
    RightScale::RightLinkLog.logger.should_receive(:error).any_number_of_times
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
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
 
  def boot(repos, bundle = nil)
    repos = @results_factory.success_results(repos)
    if bundle
      bundle = @results_factory.success_results(bundle)
    else
      bundle = @results_factory.error_results('Test')
    end
    InstanceSetup.repos = repos
    InstanceSetup.bundle = bundle

    EM.run do
      @setup.__send__(:initialize, @agent_identity.to_s)
      EM.add_periodic_timer(0.1) { check_state }
      EM.add_timer(100) { EM.stop }
    end
  end

  it 'should boot' do
    repos = RightScale::InstantiationMock.repositories
    bundle = RightScale::InstantiationMock.script_bundle('__TestScripts', '__TestScripts_too')
    boot(repos, bundle)
    res = @setup.report_state
    res.should be_success
    res.content.should == 'operational'
  end

  it 'should strand' do
    boot(RightScale::InstantiationMock.repositories)
    res = @setup.report_state
    res.should be_success
    res.content.should == 'stranded'
  end

end
