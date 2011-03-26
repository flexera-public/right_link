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

  module FileProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "file-provider-spec-0C1CE753-0089-4ac7-B689-FB74F31E90F5")).gsub("\\", "/")
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
    TEST_FILE_PATH = File.join(TEST_TEMP_PATH, 'data', 'test_file.txt')
  end

  describe Chef::Provider::File do

    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
        FileProviderSpec::TEST_TEMP_PATH,
          {
            :create_file_recipe => (
<<EOF
file "#{FileProviderSpec::TEST_FILE_PATH}" do
  mode 0644
end
EOF
          ), :fail_owner_create_file_recipe => (
<<EOF
file "#{FileProviderSpec::TEST_FILE_PATH}" do
  owner "Administrator"
  group "Administrators"
end
EOF
          ), :touch_file_recipe => (
<<EOF
file "#{FileProviderSpec::TEST_FILE_PATH}" do
  action :touch
end
EOF
          ), :delete_file_recipe => (
<<EOF
file "#{FileProviderSpec::TEST_FILE_PATH}" do
  backup 2
  action :delete
end
EOF
          )
        }
      )
    end

    def cleanup
      (FileUtils.rm_rf(FileProviderSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(FileProviderSpec::TEST_TEMP_PATH)
    end

    def backup_path
      backup_path = "#{FileProviderSpec::TEST_FILE_PATH}.chef-*"
    end

    before(:all) do
      FileUtils.mkdir_p(File.dirname(FileProviderSpec::TEST_FILE_PATH))
    end

    it_should_behave_like 'generates cookbook for chef runner'
    it_should_behave_like 'mocks logging'

    context 'file creation' do
      after(:each) do
        File.delete(FileProviderSpec::TEST_FILE_PATH) rescue nil
      end

      it "should create files on windows" do
        File.file?(FileProviderSpec::TEST_FILE_PATH).should be_false

        runner = lambda {
          RightScale::Test::ChefRunner.run_chef(
            FileProviderSpec::TEST_COOKBOOKS_PATH,
            'test::create_file_recipe') }
        runner.call.should be_true

        File.file?(FileProviderSpec::TEST_FILE_PATH).should be_true
      end

      it "should fail to create files when owner or group attribute is used on windows" do
        runner = lambda {
          RightScale::Test::ChefRunner.run_chef(
            FileProviderSpec::TEST_COOKBOOKS_PATH,
            'test::fail_owner_create_file_recipe') }
        result = false
        begin
          # note that should raise_error() does not handle NoMethodError for some reason.
          runner.call
        rescue NoMethodError
          result = true
        end
        result.should == true
      end

      it "should touch files on windows" do
        File.open(FileProviderSpec::TEST_FILE_PATH, "w") { |f| f.puts("stuff") }
        sleep 1.1  # ensure touch changes measurable time
        old_time = File.mtime(FileProviderSpec::TEST_FILE_PATH)
        runner = lambda {
          RightScale::Test::ChefRunner.run_chef(
            FileProviderSpec::TEST_COOKBOOKS_PATH,
            'test::touch_file_recipe') }
        runner.call.should be_true
        touch_time = File.mtime(FileProviderSpec::TEST_FILE_PATH)
        old_time.should < touch_time
      end
    end

    context 'file deletion' do
      before(:each) do
        backups = Dir[backup_path]
        FileUtils.rm(backups)
      end

      after(:each) do
        backups = Dir[backup_path]
        FileUtils.rm(backups)
      end

      it "should delete files on windows" do
        run_list = []
        2.times { run_list << 'test::delete_file_recipe' }
        File.open(FileProviderSpec::TEST_FILE_PATH, "w") { |f| f.puts("stuff") }
        runner = lambda {
          RightScale::Test::ChefRunner.run_chef(
            FileProviderSpec::TEST_COOKBOOKS_PATH,
            run_list) }
        runner.call.should be_true
        File.exists?(FileProviderSpec::TEST_FILE_PATH).should be_false

        backups = Dir[backup_path]
        backups.length.should == 1
      end
    end

  end

end # if windows?
