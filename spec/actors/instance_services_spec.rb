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

require File.expand_path('../spec_helper', __FILE__)
require File.expand_path('../../../actors/instance_services', __FILE__)

describe InstanceServices do

  include RightScale::SpecHelper

  before(:each) do
    @log = flexmock(RightScale::Log)
    @identity = "rs-instance-1-1"
    @agent = flexmock("agent", :identity => @identity, :terminate => true).by_default
    @services = InstanceServices.new(@agent)
  end

  context 'update_login_policy' do
    before(:each) do
      @audit_proxy = flexmock('AuditProxy')
      flexmock(RightScale::AuditProxy).should_receive(:create).and_yield(@audit_proxy)
      @audit_proxy.should_receive(:create_new_section).by_default
      @audit_proxy.should_receive(:append_info).by_default

      @mgr = RightScale::LoginManager.instance
      @policy = RightScale::LoginPolicy.new

      #update_login_policy should audit its execution
      flexmock(@services).should_receive(:send_request).
              with('/auditor/create_entry', Hash, Proc).
              and_yield(RightScale::ResultsMock.new.success_results('bogus_content'))
    end

    it 'updates the login policy' do
      flexmock(@mgr).should_receive(:update_policy).with(@policy, @identity, FlexMock.any).and_return(true).once

      @services.update_login_policy("policy" => @policy)
    end

    it 'audits failures when they occur' do
      error = "I'm sorry Dave, I can't do that."
      @audit_proxy.should_receive(:append_error).with(/#{error}/, Hash).once
      flexmock(@mgr).should_receive(:update_policy).and_raise(Exception.new(error)).once

      @services.update_login_policy("policy" => @policy)
    end
  end

  context "restart" do
    before(:each) do
      @options = {}
      flexmock(EM).should_receive(:next_tick).and_yield.once
    end

    it "restarts the instance agent" do
      @agent.should_receive(:update_configuration).never
      @agent.should_receive(:terminate).with("remote restart").once
      result = @services.restart(@options)
      result.success?.should be_true
    end

    it "updates the configuration before restarting" do
      @options = {:log_level => :debug}
      @agent.should_receive(:update_configuration).with(@options).once
      result = @services.restart(@options)
      result.success?.should be_true
    end

    it "symbolizes keys before updating the configuration" do
      @options = {"log_level" => :debug}
      @agent.should_receive(:update_configuration).with({:log_level => :debug}).once
      result = @services.restart(@options)
      result.success?.should be_true
    end

    it "logs any exceptions during next_tick" do
      @log.should_receive(:error).with("Failed restart", RuntimeError, :trace).once
      @agent.should_receive(:terminate).and_raise(RuntimeError).once
      result = @services.restart(@options)
      result.success?.should be_true
    end
  end

  context "reenroll" do
    before(:each) do
      @options = {}
      flexmock(EM).should_receive(:next_tick).and_yield.once
    end

    it "reenrolls the instance agent" do
      @agent.should_receive(:update_configuration).never
      flexmock(RightScale::ReenrollManager).should_receive(:reenroll!)
      result = @services.reenroll(@options)
      result.success?.should be_true
    end

    it "updates the configuration before reenrolling" do
      @options = {:log_level => :debug}
      @agent.should_receive(:update_configuration).with(@options).once
      flexmock(RightScale::ReenrollManager).should_receive(:reenroll!).once
      result = @services.reenroll(@options)
      result.success?.should be_true
    end

    it "symbolizes keys before updating the configuration" do
      @options = {"log_level" => :debug}
      @agent.should_receive(:update_configuration).with({:log_level => :debug}).once
      flexmock(RightScale::ReenrollManager).should_receive(:reenroll!).once
      result = @services.reenroll(@options)
      result.success?.should be_true
    end

    it "logs any exceptions during next_tick" do
      @log.should_receive(:error).with("Failed reenroll", RuntimeError, :trace).once
      flexmock(RightScale::ReenrollManager).should_receive(:reenroll!).and_raise(RuntimeError).once
      result = @services.reenroll(@options)
      result.success?.should be_true
    end
  end

  context "reboot" do
    before(:each) do
      flexmock(EM).should_receive(:next_tick).and_yield.once
      @controller = flexmock("controller", :reboot => true).by_default
      flexmock(RightScale::Platform).should_receive(:controller).and_return(@controller)
    end

    it "reboots the instance" do
      @controller.should_receive(:reboot).once
      result = @services.reboot(nil)
      result.success?.should be_true
    end

    it "closes client before rebooting" do
      client = flexmock("client")
      client.should_receive(:close).with(:receive).once
      flexmock(RightScale::RightHttpClient).should_receive(:instance).and_return(client)
      result = @services.reboot(nil)
      result.success?.should be_true
    end

    it "logs that initiating reboot" do
      @log.should_receive(:info).with("Initiate reboot using local (OS) facility").once
      @services.reboot(nil)
    end

    it "logs any exceptions during next_tick" do
      @log.should_receive(:info).once
      @log.should_receive(:error).with("Failed reboot", RuntimeError, :trace).once
      @controller.should_receive(:reboot).and_raise(RuntimeError).once
      result = @services.reboot(nil)
      result.success?.should be_true
    end
  end

  context '#system_configure' do
    before(:each) do
      @agent_identity = "rs-instance-1-1"
      @services = InstanceServices.new(@agent_identity)
    end

    it 'reload system configuration on instance' do
      flexmock(RightScale::SystemConfiguration).should_receive(:reload).and_return( true ).once
      @services.system_configure(nil)
    end
  end

end
