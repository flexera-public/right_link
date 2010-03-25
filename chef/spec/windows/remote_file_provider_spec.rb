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

  module RemoteFileProviderSpec
    TEST_TEMP_PATH = File.expand_path(File.join(Dir.tmpdir, "remote-file-provider-spec-7C75ED9D-E143-4092-9472-0A8598192B59")).gsub("\\", "/")
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
    TEST_COOKBOOK_PATH = File.join(TEST_COOKBOOKS_PATH, 'test')
    SOURCE_FILE_PATH = File.join(TEST_COOKBOOK_PATH, 'files', 'default', 'test.txt')
    TEST_FILE_PATH = File.join(TEST_TEMP_PATH, 'data', 'test.txt')

    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
        TEST_TEMP_PATH,
        {
          :create_remote_file_recipe => (
<<EOF
remote_file "#{TEST_FILE_PATH}" do
  source "#{File.basename(SOURCE_FILE_PATH)}"
  mode 0440
end
EOF
          )
        }
      )

      # template source.
      FileUtils.mkdir_p(File.dirname(SOURCE_FILE_PATH))
      source_text =
<<EOF
Remote file test
EOF
      File.open(SOURCE_FILE_PATH, "w") { |f| f.write(source_text) }
    end

    module_function :create_cookbook

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :cleanup
  end

  describe Chef::Provider::RemoteFile do

    before(:all) do
      @old_logger = Chef::Log.logger
      RemoteFileProviderSpec.create_cookbook
      FileUtils.mkdir_p(File.dirname(RemoteFileProviderSpec::TEST_FILE_PATH))
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      RemoteFileProviderSpec.cleanup
    end

    it "should create remote files on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          RemoteFileProviderSpec::TEST_COOKBOOKS_PATH,
          'test::create_remote_file_recipe') }
      runner.call.should == true
      File.file?(RemoteFileProviderSpec::TEST_FILE_PATH).should == true
      message = File.read(RemoteFileProviderSpec::TEST_FILE_PATH)
      message.chomp.should == "Remote file test"
      File.delete(RemoteFileProviderSpec::TEST_FILE_PATH)
    end

  end

end # if windows?
