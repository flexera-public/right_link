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

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

  require 'fileutils'
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module ScriptProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "script-provider-spec-46C1FDCC-DF6A-4472-B41F-409629045FD1"))
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
  end

  describe Chef::Provider::Script do
    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
        ScriptProviderSpec::TEST_TEMP_PATH,
        {
          :succeed_ruby_recipe => (
<<EOF
ruby 'test::succeed_ruby_recipe' do
  code \"puts \\\"message for stdout\\\"\\n$stderr.puts \\\"message for stderr\\\"\\n\"
end
EOF
          ), :fail_ruby_recipe => (
<<EOF
ruby 'test::fail_ruby_recipe' do
  code \"exit 99\\n\"
end
EOF
          )
        }
      )
    end

    def cleanup
      (FileUtils.rm_rf(ScriptProviderSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(ScriptProviderSpec::TEST_TEMP_PATH)
    end

    it_should_behave_like 'generates cookbook for chef runner'
    it_should_behave_like 'mocks logging'

    it "should run chef scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          ScriptProviderSpec::TEST_COOKBOOKS_PATH,
          'test::succeed_ruby_recipe') }
      runner.call.should be_true

      # note that Chef::Mixin::Command has changed to redirect both stdout and
      # stderr to info because the stderr stream is used for verbose output and
      # not necessarily errors by some Linux utilities.
      @logger.error_text.should be_empty
      @logger.info_text.should include("message for stderr")
      @logger.info_text.should include("message for stdout")
    end

    it "should raise exceptions for failing chef scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          ScriptProviderSpec::TEST_COOKBOOKS_PATH,
          'test::fail_ruby_recipe') }
      runner.should raise_error(RightScale::Exceptions::Exec)
    end

  end

end # if windows?
