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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module PowershellProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "powershell-provider-spec-17AE1F97-496D-4f07-ABD7-4D989FA3D7A6"))
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)

    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
        TEST_TEMP_PATH,
        {
          :succeed_powershell_recipe => (
<<EOF
powershell 'test::succeed_powershell_recipe' do
  source_text =
<<EOPS
  write-output "message for stdout"
EOPS
  source source_text
end
EOF
          ), :fail_powershell_recipe => (
<<EOF
powershell 'test::fail_powershell_recipe' do
  source \"exit 99\\n\"
end
EOF
          ), :expected_exit_code_recipe => (
<<EOF
powershell 'test::expected_exit_code_recipe' do
  source \"exit 77\\n\"
  returns 77
end
EOF
          ), :print_pshome_recipe => (
<<EOF
powershell 'test::print_pshome_recipe' do
  source \"$PSHOME\\n\"
end
EOF
          ), :set_env_var_recipe => (
<<EOF
powershell 'test::set_env_var_recipe' do
  source_text =
<<EOPS
  [Environment]::SetEnvironmentVariable("ps_provider_spec_machine", "ps provider spec test value", "Machine")
  [Environment]::SetEnvironmentVariable("ps_provider_spec_user", "ps provider spec test value", "User")
EOPS
  source source_text
end
EOF
          ), :check_env_var_recipe => (
<<EOF
powershell 'test::check_env_var_recipe' do
  source_text =
<<EOPS
  if ("$env:ps_provider_spec_machine" -eq "")
  {
    Write-Error "ps_provider_spec_machine env was not set"
    exit 100
  }
  if ("$env:ps_provider_spec_user" -eq "")
  {
    Write-Error "ps_provider_spec_user env was not set"
    exit 101
  }
  Write-Output "ps_provider_spec_machine and ps_provider_spec_user were set as expected"
  [Environment]::SetEnvironmentVariable("ps_provider_spec_machine", "", "Machine")
  [Environment]::SetEnvironmentVariable("ps_provider_spec_user", "", "User")
EOPS
  source source_text
end
EOF
          ), :get_chef_node_recipe => (
<<EOF
powershell 'test::get_chef_node_recipe' do
  @node[:powershell_provider_spec] = {:get_chef_node_recipe => 'get_chef_node_recipe_test_value'}
  source \"get-chefnode powershell_provider_spec,get_chef_node_recipe\"
end
EOF
          ), :set_chef_node_recipe => (
<<EOF
powershell 'test::set_chef_node_recipe' do
  source \"set-chefnode powershell_provider_spec,set_chef_node_recipe 123\"
end
EOF
          )
        }
      )
    end

    module_function :create_cookbook

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :cleanup

    class MockInstanceState
      def self.past_scripts
        return []
      end

      def self.record_script_execution(nickname)
      end
    end

  end

  # monkey patch the powershell provider class to return mock instance state.
  # the problem is that Chef instantiates the provider and we can't flexmock
  # it easily. the alternative is to pre-generate the required instance state
  # artifacts, but this seems like overkill for a standalone Chef test.
  class Chef
    class Provider
      class Powershell
        def instance_state
          return PowershellProviderSpec::MockInstanceState
        end
      end
    end
  end

  describe Chef::Provider::Powershell do

    before(:all) do
      @old_logger = Chef::Log.logger
      PowershellProviderSpec.create_cookbook
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      PowershellProviderSpec.cleanup
    end

    it "should run powershell recipes on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::succeed_powershell_recipe') }
      runner.call.should == true

      # note the powershell write-error method prints the cause of the error
      # (i.e. our script) prior to printing the error message and may insert
      # newlines into the message to wrap it for the console.
      #
      # note that Chef::Mixin::Command has changed to redirect both stdout and
      # stderr to info because the stderr stream is used for verbose output and
      # not necessarily errors by some Linux utilities. we cannot now test that
      # stdout and stderr are preserved as independent text streams because they
      # are being interleaved.
      Chef::Log.logger.error_text.should == "";
      Chef::Log.logger.info_text.gsub("\n", "").should include("message for stdout")
    end

    it "should raise exceptions for failing powershell recipes on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::fail_powershell_recipe') }
      runner.should raise_error(RightScale::Exceptions::Exec)
    end

    it "should not raise exceptions for expected exit codes on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::expected_exit_code_recipe') }
      runner.call.should == true
    end

    it "should run 32-bit powershell on all platforms" do
      platform = RightScale::RightLinkConfig[:platform]
      filesystem = platform.filesystem
      wow_path = File.join(filesystem.system_root, 'sysWOW64', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
      if File.file?(wow_path)
        # expect to run from the WOW64 directory on 64-bit Windows platforms.
        expected_pshome = File.dirname(wow_path)
      else
        # expect to run from the System32 directory on 32-bit Windows platforms.
        expected_pshome = File.join(filesystem.system_root, 'System32', 'WindowsPowerShell', 'v1.0')
      end

      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::print_pshome_recipe') }
      runner.call.should == true
      Chef::Log.logger.error_text.chomp.should == ""
      Chef::Log.logger.info_text.chomp.gsub("\\", "/").downcase.should include(expected_pshome.downcase)
    end

    it "should preserve scripted environment variable changes between powershell scripts" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          ['test::set_env_var_recipe', 'test::check_env_var_recipe']) }
      runner.call.should == true
    end

    it "should get chef nodes by powershell cmdlet" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::get_chef_node_recipe') }
      runner.call.should == true
      Chef::Log::logger.info_text.should include("get_chef_node_recipe_test_value")
    end

    it "should set chef nodes by powershell cmdlet" do
      test_node = nil
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::set_chef_node_recipe') do |chef_client|
            test_node = chef_client.node
          end }
      runner.call.should == true
      test_node[:powershell_provider_spec][:set_chef_node_recipe].should == 123
    end

  end

end # if windows?
