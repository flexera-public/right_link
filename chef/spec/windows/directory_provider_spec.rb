# Copyright (c) 2010 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation directories (the
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

  module DirectoryProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "directory-provider-spec-5DCDDAA5-DB31-4356-A8E0-DFE84179C1EA")).gsub("\\", "/")
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
    TEST_DIR_PATH = File.join(TEST_TEMP_PATH, 'data', 'test')
    TEST_SUBDIR_PATH = File.join(TEST_DIR_PATH, 'subdir1', 'subdir2')
  end

  describe Chef::Provider::Directory do

    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
              DirectoryProviderSpec::TEST_TEMP_PATH,
              {
                      :create_dir_recipe => (
                      <<EOF
directory "#{DirectoryProviderSpec::TEST_DIR_PATH}" do
  mode 0644
  not_if { File.directory?(" #{DirectoryProviderSpec::TEST_DIR_PATH} ") }
end

directory "#{DirectoryProviderSpec::TEST_SUBDIR_PATH}" do
  recursive true
  only_if \"cmd.exe /C \\\"if exist \\\"#{DirectoryProviderSpec::TEST_SUBDIR_PATH.gsub("/", "\\")}\\\" exit 1\\\"\"
end
EOF
                      ),
                      :fail_owner_create_dir_recipe => (
                      <<EOF
directory "#{DirectoryProviderSpec::TEST_DIR_PATH}" do
  owner "Administrator"
  group "Administrators"
end
EOF
                      ),
                      :delete_dir_recipe => (
                      <<EOF
directory "#{DirectoryProviderSpec::TEST_SUBDIR_PATH}" do
  action :delete
end

directory "#{DirectoryProviderSpec::TEST_DIR_PATH} " do
  recursive true
  action :delete
end
EOF
                      )
              }
      )
    end

    def cleanup
      (FileUtils.rm_rf(DirectoryProviderSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(DirectoryProviderSpec::TEST_TEMP_PATH)
    end

    before(:all) do
      FileUtils.mkdir_p(File.dirname(DirectoryProviderSpec::TEST_DIR_PATH))
    end

    after(:each) do
      FileUtils.rm_rf(DirectoryProviderSpec::TEST_DIR_PATH) rescue nil
    end

    it_should_behave_like 'generates cookbook for chef runner'
    it_should_behave_like 'mocks logging'

    it "should create directories on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
                DirectoryProviderSpec::TEST_COOKBOOKS_PATH,
                'test::create_dir_recipe') }
      runner.call.should be_true

      File.directory?(DirectoryProviderSpec::TEST_SUBDIR_PATH).should be_true
    end

    it "should fail to create directories when owner or group attribute is used on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
                DirectoryProviderSpec::TEST_COOKBOOKS_PATH,
                'test::fail_owner_create_dir_recipe') }
      result = false
      begin
        # note that should raise_error() does not handle NoMethodError for some reason.
        runner.call
      rescue NoMethodError
        result = true
      end
      result.should == true
    end

    it "should delete directories on windows" do
      run_list = []
      2.times { run_list << 'test::delete_dir_recipe' }
      FileUtils.mkdir_p(DirectoryProviderSpec::TEST_SUBDIR_PATH)
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
                DirectoryProviderSpec::TEST_COOKBOOKS_PATH,
                run_list) }
      runner.call.should be_true

      File.exists?(DirectoryProviderSpec::TEST_SUBDIR_PATH).should be_false
    end

  end

end # if windows?
