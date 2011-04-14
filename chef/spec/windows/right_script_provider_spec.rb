#
# Copyright (c) 2010 RightScale Inc
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

# note that although RightScript provider is common to Linux and Windows, the
# Linux side can rely on integration testing while Windows only has unit tests.
# these RightScript tests are therefore specific to the Powershell
# implementation of RightScripts. if there is a Linux version of these tests,
# then they should live in a "linux" spec directory.
#
# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module RightScriptProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "rightscript-provider-spec-5927C1E3-692D-43dc-912B-5FFC8963A6AF"))
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
  end

  describe Chef::Provider::RightScript do
    def create_cookbook
      recipes = {
        :succeed_right_script_recipe => (<<EOF
right_script 'test::test_right_script_parameter_recipe' do
  parameters 'TEST_VALUE' => 'correct value'
  source_file File.expand_path(File.join(File.dirname(__FILE__), '..', 'data', 'test_right_script_parameter.ps1'))
end
EOF
        ), :fail_right_script_recipe => (<<EOF
right_script 'test::test_right_script_parameter_recipe' do
  parameters 'TEST_VALUE' => 'wrong value'
  source_file File.expand_path(File.join(File.dirname(__FILE__), '..', 'data', 'test_right_script_parameter.ps1'))
end
EOF
        ), :uncaught_right_script_error_recipe => (<<EOF
right_script 'test::uncaught_right_script_error_recipe' do
  source_file File.expand_path(File.join(File.dirname(__FILE__), '..', 'data', 'uncaught_right_script_error.ps1'))
end
EOF
        )
      }

      data_files = {
        'test_right_script_parameter.ps1' => (<<EOF
if ($env:TEST_VALUE -eq \"correct value\")
{
    write \"matched expected value\"
    exit 0
}
else
{
    write \"got wrong value\"
    exit 1
}
EOF
        ), 'uncaught_right_script_error.ps1' => (<<EOF
write-output \"Line 1\"
cd c:\\a_folder_which_does_not_exist
write-output \"Line 3\"
EOF
        )
      }

      RightScale::Test::ChefRunner.create_cookbook(RightScriptProviderSpec::TEST_TEMP_PATH,
                                                   recipes,
                                                   cookbook_name = 'test',
                                                   data_files)
    end

    def cleanup
      (FileUtils.rm_rf(RightScriptProviderSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(RightScriptProviderSpec::TEST_TEMP_PATH)
    end

    it_should_behave_like 'generates cookbook for chef runner'
    it_should_behave_like 'mocks logging'
    it_should_behave_like 'mocks state'

    it "should run right scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          RightScriptProviderSpec::TEST_COOKBOOKS_PATH,
          'test::succeed_right_script_recipe') }
      runner.call.should be_true

      # FIX: currently the rightscript provider tries to read the user-data.rb file and expects the node to contain cloud specific details that do not exist in the test env.
      # commented until those expectations are mocked out
      #@logger.error_text.should be_empty

      @logger.info_text.gsub("\n", "").should include("matched expected value")
    end

    it "should raise exceptions for failing right scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          RightScriptProviderSpec::TEST_COOKBOOKS_PATH,
          'test::fail_right_script_recipe') }
      runner.should raise_exception(RightScale::Exceptions::Exec)
    end

    it "should fail when a right script succeeds with a non-empty error list" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
                RightScriptProviderSpec::TEST_COOKBOOKS_PATH,
                'test::uncaught_right_script_error_recipe') }
      runner.should raise_exception(RightScale::Exceptions::Exec)
      message_format = <<-EOF
Line 1
Set-Location : Cannot find path 'C:\\a_folder_which_does_not_exist' because it does not exist.
At .*:2 char:3
  + cd <<<<  c:\\a_folder_which_does_not_exist
  + CategoryInfo          : ObjectNotFound: (C:\\a_folder_which_does_not_exist:String) [Set-Location], ItemNotFoundException
  + FullyQualifiedErrorId : PathNotFound,Microsoft.PowerShell.Commands.SetLocationCommand
Line 3
WARNING: Script exited successfully but $Error contained 1 error(s).
EOF
      # remove newlines and spaces
      expected_message = Regexp.escape(message_format.gsub(/\s+/, ""))

      # un-escape the escaped regex strings
      expected_message.gsub!("\\.\\*", ".*")
      logs = @logger.info_text.gsub(/\s+/, "")

      # should contain the expected exception
      logs.should match(expected_message)
    end
  end

end # if windows?
