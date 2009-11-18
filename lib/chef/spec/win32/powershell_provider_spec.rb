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

require File.join(File.dirname(__FILE__), '..', 'spec_helper')

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

module PowershellProviderSpec

  class StubAuditorProxy
    def self.append_info(text)
    end
  end

  class MockInstanceState
    def self.past_scripts
      return []
    end

    def self.record_script_execution(nickname)
    end
  end

  class MockStatus
    attr_reader :exitstatus

    def initialize(exitstatus = 0)
      @exitstatus = exitstatus
    end

    def success?
      return 0 == @exitstatus
    end
  end

end

describe Chef::Provider::PowerShell do
  before(:each) do
    @node = flexmock('Chef::Node')
    @node.should_ignore_missing
    @new_resource = Chef::Resource::PowerShell.new("testing")
    @new_resource.source "write-output \"Running powershell v1.0 script\""
  end

  it "should be registered with the default platform hash" do
    Chef::Platform.platforms[:default][:powershell].should_not be_nil
  end

  it "should return a Chef::Provider::PowerShell object" do
    provider = Chef::Provider::PowerShell.new(@node, @new_resource)
    provider.should be_a_kind_of(Chef::Provider::PowerShell)
  end

  it "should raise an exception if run fails" do
    provider = Chef::Provider::PowerShell.new(@node, @new_resource)
    flexmock(provider).should_receive(:create_auditor_proxy).once.and_return(PowershellProviderSpec::StubAuditorProxy)
    flexmock(provider).should_receive(:instance_state).once.and_return(PowershellProviderSpec::MockInstanceState)
    flexmock(provider).should_receive(:run_script_file).once.and_return(PowershellProviderSpec::MockStatus.new(1))
    lambda{ provider.action_run }.should raise_error(RightScale::Exceptions::Exec)
  end

  it "should return true if run succeeds" do
    provider = Chef::Provider::PowerShell.new(@node, @new_resource)
    flexmock(provider).should_receive(:create_auditor_proxy).once.and_return(PowershellProviderSpec::StubAuditorProxy)
    flexmock(provider).should_receive(:instance_state).once.and_return(PowershellProviderSpec::MockInstanceState)
    flexmock(provider).should_receive(:run_script_file).once.and_return(PowershellProviderSpec::MockStatus.new(0))
    provider.action_run.should == true
  end
end

end # if windows?
