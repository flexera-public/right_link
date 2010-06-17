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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

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
          ), :get_current_resource_recipe => (
<<EOF
powershell 'test::get_current_resource_recipe' do
  source_text =
<<EOPS
  $currentResource = Get-CurrentResource ""
  if ($currentResource)
  {
    Write-Error "Unexpected current resource for powershell provider"
    exit 100
  }
EOPS
  source source_text
end
EOF
          ), :set_current_resource_recipe => (
<<EOF
powershell 'test::set_current_resource_recipe' do
  source_text =
<<EOPS
  $Error.clear()
  Set-CurrentResource "" 123
  Set-CurrentResource my_hash @{a="A"}
  if (2 -ne $Error.count)
  {
    Write-Error "Expected setting current resource to fail for powershell provider"
    exit 100
  }
EOPS
  source source_text
end
EOF
          ), :get_new_resource_recipe => (
<<EOF
powershell 'test::get_new_resource_recipe' do
  returns 10
  source_text =
<<EOPS
  $newResource = Get-NewResource ""
  if ($newResource)
  {
    $returnsValue = Get-NewResource returns
    if ($returnsValue -eq 10)
    {
      if ($returnsValue -ne $newResource.returns)
      {
        Write-Error "Same value queried by two different paths were not equal"
        exit 100
      }
      else
      {
        exit 10
      }
    }
    else
    {
      Write-Error "unable to query new resource returns value"
      exit 101
    }
  }
  else
  {
    Write-Error "unable to query new resource"
    exit 102
  }
EOPS
  source source_text
end
EOF
          ), :set_new_resource_recipe => (
<<EOF
powershell 'test::set_new_resource_recipe' do
  parameters "a"=>"A", "b"=>"B"
  source_text =
<<EOPS
  $Error.clear()
  Set-NewResource "" 123
  if (1 -ne $Error.count)
  {
    Write-Error "Expected setting root of new resource to fail"
    exit 100
  }
  $Error.clear()
  $parameters = Get-NewResource parameters
  if (0 -ne $Error.count)
  {
    Write-Error "Failed to get parameters value"
    exit 101
  }
  $parameters.x = "X"
  $parameters.y = "Y"
  Set-NewResource parameters -HashValue $parameters
  if (0 -ne $Error.count)
  {
    Write-Error "Failed to set parameters value"
    exit 102
  }
  $parameters = $NULL
  $parameters = Get-NewResource parameters
  if ($parameters.a -ne "A" -or $parameters.b -ne "B" -or $parameters.x -ne "X" -or $parameters.y -ne "Y")
  {
    $parameters > "powershell_provider_spec_set_new_resource_recipe.txt"
    exit 103
  }
EOPS
  source source_text
end
EOF
          ), :debug_output_recipe => (
<<EOF
powershell 'test::debug_output_recipe' do
  Chef::Log.logger.level = Logger::DEBUG
  source_text =
<<EOPS
  Write-Verbose "verbose message"
  Write-Debug "debug message"
EOPS
  source source_text
end
EOF
          ), :execution_policy_recipe => (
<<EOF
powershell 'test::execution_policy_recipe' do
  source_text =
<<EOPS
  $local_machine_policy = get-executionpolicy -Scope LocalMachine
  if($local_machine_policy -ne "Restricted")
  {
    Write-Error "Expected get-executionpolicy -Scope LocalMachine == 'Restricted', but was $local_machine_policy"
    exit 100
  }

  $process_policy = get-executionpolicy -Scope Process
  if ($process_policy -ne "RemoteSigned")
  {
    Write-Error "Expected get-executionpolicy -Scope Process == 'RemoteSigned', but was $process_policy"
    exit 101
  }
EOPS
  source source_text
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
      runner.should raise_exception(RightScale::Exceptions::Exec)
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

    it "should fail to get current resource by powershell cmdlet for powershell provider" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::get_current_resource_recipe') }
      runner.call.should == true
    end

    it "should fail to set current resource by powershell cmdlet for powershell provider" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::set_current_resource_recipe') }
      runner.call.should == true
    end

    it "should get new resource by powershell cmdlet" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::get_new_resource_recipe') }
      runner.call.should == true
    end

    it "should set new resource by powershell cmdlet" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::set_new_resource_recipe') }
      runner.call.should == true
    end

    it "should write debug to output stream when debugging is enabled" do
      old_level = Chef::Log.level
      begin
        runner = lambda {
          RightScale::Test::ChefRunner.run_chef(
            PowershellProviderSpec::TEST_COOKBOOKS_PATH,
            'test::debug_output_recipe') }
        runner.call.should == true

        debug_output = Chef::Log.logger.info_text
        debug_output.should include("debug message")
        debug_output.should include("verbose message")
      ensure
        Chef::Log.level = old_level
      end
    end

    it "should change the execution policy of the current process, but not the local machine" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::execution_policy_recipe') }
      runner.call.should == true

      # ensure the policy is not changed after the test
      (`powershell -command get-executionpolicy -Scope LocalMachine` =~ /Restricted/).should_not be_nil
      (`powershell -command get-executionpolicy -Scope Process` =~ /Undefined/).should_not be_nil
    end
  end

end # if windows?
