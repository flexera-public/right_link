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
require 'thread'

describe Chef::Provider::ServerCollection do

  before(:each) do
    @result = {}
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

  it 'should timeout appropriately' do
    pending 'needs to be refactored - the wrong things are mocked and tests timeout by coincidence'
    old_timeout = Chef::Provider::ServerCollection::QUERY_TIMEOUT
    begin
      Chef::Provider::ServerCollection.const_set(:QUERY_TIMEOUT, 0.5)
      mapper_proxy = flexmock('MapperProxy')
      flexmock(RightScale::MapperProxy).should_receive(:instance).and_return(mapper_proxy).by_default
      mapper_proxy.should_receive(:send_retryable_request).and_yield(nil)
      perform_load
      @provider.instance_variable_get(:@node)[:server_collection]['resource_name'].should == {}
    ensure
      Chef::Provider::ServerCollection.const_set(:QUERY_TIMEOUT, old_timeout)
    end
  end

  it 'should timeout when request for tags takes too long' do
    pending 'notions of new tests'
#    @mock_cook.should_receive(:send_retryable_request).and_ ???
#    perform_load
#    @completed.should be_false
  end

  it 'should populate server collection when tags exits' do
    pending 'notions of new tests'
#    @result = {'server-1' => {:tags => ['tag1', 'tag2']}, 'server-2' => {:tags => ['tag1', 'tag3']}}
#    @is_done = lambda { @provider.node[:server_collection]['resource_name'] == @result }
#    @mock_cook = flexmock('Cook')
#    flexmock(RightScale::Cook).should_receive(:instance).and_return(@mock_cook).by_default
#    @mock_cook.should_receive(:send_retryable_request).and_yield(RightScale::OperationResult.new(0, @result))
#    perform_load
#    @completed.should be_true
  end

  it 'should not populate server collection when request fails' do
    pending 'notions of new tests'
#    @mock_cook = flexmock('Cook')
#    flexmock(RightScale::Cook).should_receive(:instance).and_return(@mock_cook).by_defaul
#    @mock_cook.should_receive(:send_retryable_request).and_yield(RightScale::OperationResult.new(1, nil))
#    perform_load
#    @completed.should be_true
  end

end
