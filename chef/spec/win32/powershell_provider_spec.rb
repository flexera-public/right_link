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

  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module PowershellProviderSpec

    # unique directory for temporary files.
    TEST_TEMP_PATH = File.expand_path(File.join(Dir.tmpdir, "powershell-provider-spec-17AE1F97-496D-4f07-ABD7-4D989FA3D7A6"))

    # cookbooks (note that Chef fails if backslashes appear cookbook paths)
    TEST_COOKBOOKS_PATH = File.join(TEST_TEMP_PATH, "cookbooks").gsub("\\", "/")

    def create_test_cookbook
      test_cookbook_path = File.join(TEST_COOKBOOKS_PATH, 'test')
      test_recipes_path = File.join(test_cookbook_path, 'recipes')
      FileUtils.mkdir_p(test_recipes_path)

      # successful powershell resource using powershell provider.
      succeed_powershell_recipe =
<<EOF
powershell 'test::succeed_powershell_recipe' do
  source \"write-output \\\"message for stdout\\\"\\nwrite-error \\\"message for stderr\\\"\\n\"
end
EOF
      succeed_powershell_recipe_path = File.join(test_recipes_path, 'succeed_powershell_recipe.rb')
      File.open(succeed_powershell_recipe_path, "w") { |f| f.write(succeed_powershell_recipe) }

      # failing powershell resource.
      fail_powershell_recipe =
<<EOF
powershell 'test::fail_powershell_recipe' do
  source \"exit 99\\n\"
end
EOF
      fail_powershell_recipe_path = File.join(test_recipes_path, 'fail_powershell_recipe.rb')
      File.open(fail_powershell_recipe_path, "w") { |f| f.write(fail_powershell_recipe) }

      # print PSHOME variable.
      print_pshome_recipe =
<<EOF
powershell 'test::print_pshome_recipe' do
  source \"$PSHOME\\n\"
end
EOF
      print_pshome_recipe_path = File.join(test_recipes_path, 'print_pshome_recipe.rb')
      File.open(print_pshome_recipe_path, "w") { |f| f.write(print_pshome_recipe) }

      # metadata
      metadata =
<<EOF
maintainer "RightScale, Inc."
version    "0.1"
recipe     "test::succeed_powershell_recipe", "Succeeds running a powershell script"
recipe     "test::fail_powershell_recipe", "Fails running a powershell script"
recipe     "test::print_pshome_recipe", "Prints the PSHOME variable"
EOF
      metadata_path = test_recipes_path = File.join(test_cookbook_path, 'metadata.rb')
      File.open(metadata_path, "w") { |f| f.write(metadata) }
    end

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :create_test_cookbook, :cleanup

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
      PowershellProviderSpec.create_test_cookbook
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      PowershellProviderSpec.cleanup
    end

    it "should run chef scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::succeed_powershell_recipe') }
      runner.call.should == true

      # note the powershell write-error method prints the cause of the error
      # (i.e. our script) prior to printing the error message and may insert
      # newlines into the message to wrap it for the console.
      Chef::Log.logger.error_text.gsub("\n", "").should include("message for stderr")
      Chef::Log.logger.info_text.should include("message for stdout")
    end

    it "should raise exceptions for failing chef scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          PowershellProviderSpec::TEST_COOKBOOKS_PATH,
          'test::fail_powershell_recipe') }
      runner.should raise_error(RightScale::Exceptions::Exec)
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

  end

end # if windows?
