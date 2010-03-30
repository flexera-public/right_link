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

# Need to monkey patch to test, flexmock doens't cut it as we need to
# define a custom behavior that yield and you can't yield from a block
module RightScale
  class RequestForwarder
    def self.query_tags(_, &blk)
      EM.next_tick do
         yield @@res if @@res
      end                                    
    end
    def self.set_query_tags_result(res)
      @@res = Result.new('token', 'to', res, 'from')
    end
  end
end

describe Chef::Provider::ServerCollection do

  before(:each) do
    @agent_hash = {'agent_id_1' => { 'tags' => ['tag1', 'tag2'] },
                   'agent_id_2' => { 'tags' => ['tag1', 'tag3'] } }
    @result = {}
    @agent_hash.each { |k, v| @result[k] = v['tags'] }
    @resource = Chef::Resource::ServerCollection.new("test")
    @provider = Chef::Provider::ServerCollection.new(nil, @resource)
    @provider.instance_variable_set(:@node, {:server_collection => { 'resource_name' => nil }})
    @provider.instance_variable_set(:@new_resource, flexmock('resource', :name => 'resource_name', :tags => 'tag1', :agent_ids => nil))
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
    RightScale::RequestForwarder.set_query_tags_result(@agent_hash)
    perform_load
    @provider.instance_variable_get(:@node)[:server_collection]['resource_name'].should == @result
  end

  it 'should timeout appropriately' do
    old_timeout = Chef::Provider::ServerCollection::QUERY_TIMEOUT
    begin
      Chef::Provider::ServerCollection.const_set(:QUERY_TIMEOUT, 0.5)
      RightScale::RequestForwarder.set_query_tags_result(nil)
      perform_load
      @provider.instance_variable_get(:@node)[:server_collection]['resource_name'].should == {}
    ensure
      Chef::Provider::ServerCollection.const_set(:QUERY_TIMEOUT, old_timeout)
    end
  end

end
