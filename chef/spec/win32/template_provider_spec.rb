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

  module TemplateProviderSpec
    # unique directory for temporary files.
    # note that Chef fails if backslashes appear in cookbook paths.
    TEST_TEMP_PATH = File.expand_path(File.join(Dir.tmpdir, "template-provider-spec-3FEFA392-2624-4e6d-8279-7D0BEB1CC7A2")).gsub("\\", "/")
    TEST_COOKBOOKS_PATH = File.join(TEST_TEMP_PATH, 'cookbooks')
    TEST_COOKBOOK_PATH = File.join(TEST_COOKBOOKS_PATH, 'test')
    SOURCE_FILE_PATH = File.join(TEST_COOKBOOK_PATH, 'templates', 'default', 'test.erb')
    TEST_FILE_PATH = File.join(TEST_TEMP_PATH, 'data', 'template_file.txt')

    def create_test_cookbook
      test_recipes_path = File.join(TEST_COOKBOOK_PATH, 'recipes')
      FileUtils.mkdir_p(test_recipes_path)
      FileUtils.mkdir_p(File.dirname(SOURCE_FILE_PATH))

      # template source.
      source_text =
<<EOF
<%= @var1 %> can work in <%= @var2 %>.
EOF
      File.open(SOURCE_FILE_PATH, "w") { |f| f.write(source_text) }

      # create file using template provider.
      create_templated_file_recipe =
<<EOF
template "#{TEST_FILE_PATH}" do
  source "#{File.basename(SOURCE_FILE_PATH)}"
  mode 0440
  variables( :var1 => 'Chef', :var2 => 'Windows' )
end
EOF
      create_templated_file_recipe_path = File.join(test_recipes_path, 'create_templated_file_recipe.rb')
      File.open(create_templated_file_recipe_path, "w") { |f| f.write(create_templated_file_recipe) }

      # metadata
      metadata =
<<EOF
maintainer "RightScale, Inc."
version    "0.1"
recipe     "test::create_templated_file_recipe", "Creates a file from a template"
EOF
      metadata_path = test_recipes_path = File.join(TEST_COOKBOOK_PATH, 'metadata.rb')
      File.open(metadata_path, "w") { |f| f.write(metadata) }
    end

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :create_test_cookbook, :cleanup
  end

  describe Chef::Provider::Template do

    before(:all) do
      @old_logger = Chef::Log.logger
      TemplateProviderSpec.create_test_cookbook
      FileUtils.mkdir_p(File.dirname(TemplateProviderSpec::TEST_FILE_PATH))
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      TemplateProviderSpec.cleanup
    end

    it "should create templated files on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          TemplateProviderSpec::TEST_COOKBOOKS_PATH,
          'test::create_templated_file_recipe') }
      runner.call.should == true
      File.file?(TemplateProviderSpec::TEST_FILE_PATH).should == true
      message = File.read(TemplateProviderSpec::TEST_FILE_PATH)
      message.chomp.should == "Chef can work in Windows."
      File.delete(TemplateProviderSpec::TEST_FILE_PATH)
    end

  end

end # if windows?
