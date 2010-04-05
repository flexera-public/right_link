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
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'windows', 'chef_node_server'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "run-chef-node-server-9791A30A-3FCE-4f5b-AEEB-72D82B3689AE"))
TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)

RightScale::Test::ChefRunner.run_chef_as_server(TEST_COOKBOOKS_PATH, []) do |chef_client|
  Chef::Log.logger.level = Logger::DEBUG
  chef_node_server = ::RightScale::Windows::ChefNodeServer.new(:node => chef_client.node, :logger => Chef::Log.logger)
  chef_node_server.current_resource = Mash.new(:a => 'A', :b => 'B')
  chef_node_server.new_resource = Chef::Resource::Powershell.new("test")
  chef_node_server.start
end
