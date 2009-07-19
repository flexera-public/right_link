require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'right_popen', 'lib', 'right_popen')
require File.join(File.dirname(__FILE__), 'auditor_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')
require 'instance_lib'
require 'instance_setup'

describe InstanceSetup do

  include RightScale::SpecHelpers

  before(:each) do
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1)
    @setup = InstanceSetup.allocate
    @setup.stub!(:request)
    @setup.stub!(:configure_repositories).and_return(RightScale::OperationResult.success)
    @auditor = RightScale::AuditorProxyMock.new
    RightScale::AuditorProxy.stub!(:new).and_return(@auditor)
    @results_factory = RightScale::NaniteResultsMock.new
    RightScale::RightLinkLog.logger.stub!(:error)
    RightScale::RightLinkLog.logger.stub!(:debug)
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
    @setup.should_receive(:request).with("/booter/set_r_s_version", :agent_identity => @agent_identity.to_s, :r_s_version => 5).and_yield(@results_factory.success_results)
    @setup.should_receive(:request).with("/booter/get_repositories", @agent_identity.to_s).and_yield(repos)
    options = { :agent_identity => @agent_identity.to_s, :audit_id => @auditor.audit_id }
    @setup.should_receive(:request).with("/booter/get_boot_bundle", options).and_yield(bundle)
    EM.run do
      @setup.__send__(:initialize, @agent_identity.to_s)
      EM.add_periodic_timer(0.1) { check_state }
      EM.add_timer(10) { EM.stop }
    end
  end

  it 'should boot' do
    repos = RightScale::InstantiationMock.repositories
    bundle = RightScale::InstantiationMock.script_bundle('__TestScripts', '__TestScripts_too')
    lambda { boot(repos, bundle) }.should_not raise_error
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
