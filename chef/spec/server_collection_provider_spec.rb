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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'instance', 'request_forwarder'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'instance', 'dev_state'))
require 'thread'

describe Chef::Provider::ServerCollection do

  before(:all) do
    @old_request_forwarder = RightScale::RequestForwarder

    # Need to monkey patch to test, flexmock doesn't cut it as we need to
    # define a custom behavior that yields and you can't yield from a block
    module RightScale
      class RequestForwarder
        def self.request(type, payload = '', opts = {}, &blk)
          EM.next_tick do
            yield @@res if @@res
          end
        end
        def self.set_list_agents_result(res)
          @@res = Result.new('token', 'to', res, 'from')
        end
      end
    end
  end

  before(:each) do
    @agents = {'agent_id1' => { 'tags' => ['tag1', 'tag2'] },
               'agent_id2' => { 'tags' => ['tag1', 'tag3'] } }
    @result = {}
    @agents.each { |k, v| @result[k] = v['tags'] }
    @resource = Chef::Resource::ServerCollection.new("test")
    @provider = Chef::Provider::ServerCollection.new(nil, @resource)
    @provider.instance_variable_set(:@node, {:server_collection => { 'resource_name' => nil }})
    @provider.instance_variable_set(:@new_resource, flexmock('resource', :name => 'resource_name', :tags => 'tag1', :agent_ids => nil))
  end

  after(:all) do
    RightScale::RequestForwarder = @old_request_forwarder
  end

  def perform_load
    # Call the chef provider in the 'Chef thread'
    Thread.new do
      @provider.action_load
    end

    # Run the EM thread and poll for result
    EM.run do
      EM.add_periodic_timer(0.1) do
        succeeded = @provider.instance_variable_get(:@node)[:server_collection]['resource_name'] == @result
        EM.stop if succeeded
      end
      EM.add_timer(1) { EM.stop }
    end
  end

  it 'should load the collection synchronously' do
    RightScale::RequestForwarder.set_list_agents_result({ 'mapper_id1' => RightScale::OperationResult.success(@agents) })
    perform_load
    @provider.instance_variable_get(:@node)[:server_collection]['resource_name'].should == @result
  end

  it 'should timeout appropriately' do
    old_timeout = Chef::Provider::ServerCollection::QUERY_TIMEOUT
    begin
      Chef::Provider::ServerCollection.const_set(:QUERY_TIMEOUT, 0.5)
      RightScale::RequestForwarder.set_list_agents_result(nil)
      perform_load
      @provider.instance_variable_get(:@node)[:server_collection]['resource_name'].should == {}
    ensure
      Chef::Provider::ServerCollection.const_set(:QUERY_TIMEOUT, old_timeout)
    end
  end

end
