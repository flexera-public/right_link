#
# Copyright (c) 2010-2013 RightScale Inc
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
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'windows', 'chef_node_server'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

class RunChefNodeServer
  TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "run-chef-node-server-6d7ead9d4447ed3cbbb0bc8cd906b88e"))
  TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)

  def self.create_cookbook
    RightScale::Test::ChefRunner.create_cookbook(TEST_TEMP_PATH, {})
  end

  def self.cleanup
    (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
  end
end

RunChefNodeServer.create_cookbook  # chef fails unless there is at least one cookbook on path

RightScale::Test::ChefRunner.run_chef_as_server(RunChefNodeServer::TEST_COOKBOOKS_PATH, []) do |chef_client|
  Chef::Log.logger.level = Logger::DEBUG
  RightScale::Windows::ChefNodeServer.instance.start(:node => chef_client.node)
  RightScale::Windows::ChefNodeServer.instance.current_resource = Mash.new(:a => 'A', :b => 'B')
  RightScale::Windows::ChefNodeServer.instance.new_resource = Chef::Resource::Powershell.new("test")
end
