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
require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')

require 'chef'
require 'log_resource'
require 'log_provider_chef'

describe Chef::Provider::Log::ChefLog do

  before(:each) do
    @log_str = "this is my test string to log"
    @node = mock("Chef::Node", :null_object => true)   
  end  

  it "should be registered with the default platform hash" do
    Chef::Platform.platforms[:default][:log].should_not be_nil
  end

  it "should write the string to the Chef::Log object at default level (info)" do
      @new_resource = Chef::Resource::Log.new(@log_str)
      @provider = Chef::Provider::Log::ChefLog.new(@node, @new_resource)
      Chef::Log.should_receive(:info).with(@log_str).and_return(true)
      @provider.write
  end
  
  it "should write the string to the Chef::Log object at debug level" do
      @new_resource = Chef::Resource::Log.new(@log_str)
      @new_resource.level :debug
      @provider = Chef::Provider::Log::ChefLog.new(@node, @new_resource)
      Chef::Log.should_receive(:debug).with(@log_str).and_return(true)
      @provider.write
  end

  it "should write the string to the Chef::Log object at info level" do
      @new_resource = Chef::Resource::Log.new(@log_str)
      @new_resource.level :info
      @provider = Chef::Provider::Log::ChefLog.new(@node, @new_resource)
      Chef::Log.should_receive(:info).with(@log_str).and_return(true)
      @provider.write
  end
  
  it "should write the string to the Chef::Log object at warn level" do
      @new_resource = Chef::Resource::Log.new(@log_str)
      @new_resource.level :warn
      @provider = Chef::Provider::Log::ChefLog.new(@node, @new_resource)
      Chef::Log.should_receive(:warn).with(@log_str).and_return(true)
      @provider.write
  end
  
  it "should write the string to the Chef::Log object at error level" do
      @new_resource = Chef::Resource::Log.new(@log_str)
      @new_resource.level :error
      @provider = Chef::Provider::Log::ChefLog.new(@node, @new_resource)
      Chef::Log.should_receive(:error).with(@log_str).and_return(true)
      @provider.write
  end
  
  it "should write the string to the Chef::Log object at fatal level" do
      @new_resource = Chef::Resource::Log.new(@log_str)
      @new_resource.level :fatal
      @provider = Chef::Provider::Log::ChefLog.new(@node, @new_resource)
      Chef::Log.should_receive(:fatal).with(@log_str).and_return(true)
      @provider.write
  end
  
end
