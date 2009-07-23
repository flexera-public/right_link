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
require 'dns_resource'
require 'dns_provider_dnsmadeeasy'

describe Chef::Provider::DnsMadeEasy do
  before(:each) do
    @node = mock("Chef::Node", :null_object => true)
   
  end
  
  it "should be registered with the default platform hash" do
    Chef::Platform.platforms[:default][:dns].should_not be_nil
  end

  it "should return a Chef::Provider::Dns object" do
    @new_resource = mock("Chef::Resource", :null_object => true)
    provider = Chef::Provider::DnsMadeEasy.new(@node, @new_resource)
    provider.should be_a_kind_of(Chef::Provider::DnsMadeEasy)
  end

  it "should return raise an error in test mode" do
    @new_resource = Chef::Resource::Dns.new("test")
    provider = Chef::Provider::DnsMadeEasy.new(@node, @new_resource)
    provider.testing = true
    Chef::Log.should_receive(:debug).once
    Chef::Log.should_receive(:info).once
    lambda{ provider.action_register }.should raise_error()
  end

  #
  # below this is actually a functional test. (please use your own dnsmadeeasy dns_name)
  #  
  #   dns_name = "NNNNNNN" # your_record.test.rightscale.com
  #   ip_addr = "75.101.174.1"
  #   username = "payless"
  #   passwd = "scalemore!"
  #   it "should update #{dns_name} to #{ip_addr}" do
  #     @new_resource = Chef::Resource::Dns.new(dns_name)
  #     @new_resource.user username
  #     @new_resource.passwd passwd
  #     @new_resource.ip_address ip_addr
  #     
  #       
  #     provider = Chef::Provider::DnsMadeEasy.new(@node, @new_resource)
  #     provider.testing = false
  #     lambda{ provider.action_register }.should_not raise_error()
  #   end

end



