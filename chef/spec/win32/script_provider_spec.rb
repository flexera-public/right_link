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
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.expand_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module ScriptProviderSpec
    # unique directory for temporary files.
    TEST_TEMP_PATH = File.expand_path(File.join(Dir.tmpdir, "script-provider-spec-46C1FDCC-DF6A-4472-B41F-409629045FD1"))

    # cookbooks (note that Chef fails if backslashes appear cookbook paths)
    TEST_COOKBOOKS_PATH = File.join(TEST_TEMP_PATH, "cookbooks").gsub("\\", "/")

    def create_test_cookbook
      test_cookbook_path = File.join(TEST_COOKBOOKS_PATH, 'test')
      test_recipes_path = File.join(test_cookbook_path, 'recipes')
      FileUtils.mkdir_p(test_recipes_path)

      # successful ruby resource using script provider.
      succeed_ruby_recipe =
<<EOF
ruby 'test::succeed_ruby_recipe' do
  code \"puts \\\"message for stdout\\\"\\n$stderr.puts \\\"message for stderr\\\"\\n\"
end
EOF
      succeed_ruby_recipe_path = File.join(test_recipes_path, 'succeed_ruby_recipe.rb')
      File.open(succeed_ruby_recipe_path, "w") { |f| f.write(succeed_ruby_recipe) }

      # failing ruby resource.
      fail_ruby_recipe =
<<EOF
ruby 'test::fail_ruby_recipe' do
  code \"exit 99\\n\"
end
EOF
      fail_ruby_recipe_path = File.join(test_recipes_path, 'fail_ruby_recipe.rb')
      File.open(fail_ruby_recipe_path, "w") { |f| f.write(fail_ruby_recipe) }

      # metadata
      metadata =
<<EOF
maintainer "RightScale, Inc."
version    "0.1"
recipe     "test::succeed_ruby_recipe", "Succeeds running a ruby script"
recipe     "test::fail_ruby_recipe", "Fails running a ruby script"
EOF
      metadata_path = test_recipes_path = File.join(test_cookbook_path, 'metadata.rb')
      File.open(metadata_path, "w") { |f| f.write(metadata) }
    end

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :create_test_cookbook, :cleanup
  end

  describe Chef::Provider::Script do

    before(:all) do
      @old_logger = Chef::Log.logger
      ScriptProviderSpec.create_test_cookbook
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      ScriptProviderSpec.cleanup
    end

    it "should run chef scripts on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          ScriptProviderSpec::TEST_COOKBOOKS_PATH,
          'test::succeed_ruby_recipe') }
      runner.call.should == true
      Chef::Log.logger.error_text.should include("message for stderr")
      Chef::Log.logger.info_text.should include("message for stdout")
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
