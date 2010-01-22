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
      def initialize
        @info = ""
        @output = ""
        @error = ""
      end

      attr_reader :info, :output, :error

      def append_info(info)
        @info << info
      end

      def append_output(output)
        @output << output
      end

      def append_error(error)
        @error << error
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

  describe Chef::Provider::Powershell do

    before(:each) do
      @node = flexmock('Chef::Node')
      @node.should_ignore_missing
      @new_resource = Chef::Resource::Powershell.new("testing")
      @new_resource.source "write-output \"Running powershell v1.0 script\""
    end

    it "should be registered with the default platform hash" do
      Chef::Platform.platforms[:default][:powershell].should_not be_nil
    end

    it "should return a Chef::Provider::Powershell object" do
      provider = Chef::Provider::Powershell.new(@node, @new_resource)
      provider.should be_a_kind_of(Chef::Provider::Powershell)
    end

    it "should raise an exception if run fails" do
      provider = Chef::Provider::Powershell.new(@node, @new_resource)
      flexmock(provider).should_receive(:create_auditor_proxy).once.and_return(PowershellProviderSpec::StubAuditorProxy.new)
      flexmock(provider).should_receive(:instance_state).once.and_return(PowershellProviderSpec::MockInstanceState)
      flexmock(provider).should_receive(:run_script_file).once.and_return(PowershellProviderSpec::MockStatus.new(1))
      lambda{ provider.action_run }.should raise_error(RightScale::Exceptions::Exec)
    end

    it "should return true if run succeeds" do
      provider = Chef::Provider::Powershell.new(@node, @new_resource)
      flexmock(provider).should_receive(:create_auditor_proxy).once.and_return(PowershellProviderSpec::StubAuditorProxy.new)
      flexmock(provider).should_receive(:instance_state).once.and_return(PowershellProviderSpec::MockInstanceState)
      flexmock(provider).should_receive(:run_script_file).once.and_return(PowershellProviderSpec::MockStatus.new(0))
      provider.action_run.should == true
    end

    it "should run 32-bit powershell on all platforms" do
      @new_resource.source("$PSHOME\n") # echoes value of PSHOME variable to stdout
      provider = Chef::Provider::Powershell.new(@node, @new_resource)
      auditor = PowershellProviderSpec::StubAuditorProxy.new
      flexmock(provider).should_receive(:create_auditor_proxy).once.and_return(auditor)
      flexmock(provider).should_receive(:instance_state).once.and_return(PowershellProviderSpec::MockInstanceState)

      platform = RightScale::RightLinkConfig[:platform]
      filesystem = platform.filesystem
      wow_path = File.join(filesystem.system_root, 'sysWOW64', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
      if File.file?(wow_path)
        expected_pshome = File.dirname(wow_path)
      else
        expected_pshome = File.join(filesystem.system_root, 'System32', 'WindowsPowerShell', 'v1.0')
      end

      # set threadpool size to 1 to force queueing of deferred blocks.
      EM.threadpool_size = 1

      done = false
      action_run_result = false
      EM.run do
        EM.defer do
          action_run_result = provider.action_run
          done = true
        end
        timer = EM::PeriodicTimer.new(0.1) do
          if done
            timer.cancel
            EM.stop
          end
        end
      end
      action_run_result.should == true
      auditor.error.chomp.should == ""
      auditor.output.chomp.gsub("\\", "/").downcase.should == expected_pshome.downcase
    end

  end

end # if windows?
