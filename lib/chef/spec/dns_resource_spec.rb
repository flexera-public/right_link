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

describe Chef::Resource::Dns do
  
  before(:each) do
    @resource = Chef::Resource::Dns.new("testing")
  end  
 
  it "should create a new Chef::Resource::Dns" do
      @resource.should be_a_kind_of(Chef::Resource)
      @resource.should be_a_kind_of(Chef::Resource::Dns)
    end

  it "should have a name of dns" do
    @resource.resource_name.should == :dns
  end

  it "default action should be register" do
    @resource.action == :register
  end
  
  it "should accept a vaild user option" do
    lambda { @resource.user "someuser" }.should_not raise_error(ArgumentError)
    lambda { @resource.user 123 }.should raise_error(ArgumentError)
    lambda { @resource.user :unsupported }.should raise_error(ArgumentError)
  end
  
  it "should accept a vaild password option" do
    lambda { @resource.passwd "somepassword" }.should_not raise_error(ArgumentError)
    lambda { @resource.passwd 123 }.should raise_error(ArgumentError)
    lambda { @resource.passwd :unsupported }.should raise_error(ArgumentError)
  end
  
  it "should accept a vaild ip_address option" do
    lambda { @resource.ip_address "255.255.255.255" }.should_not raise_error(ArgumentError)
    lambda { @resource.ip_address "0.0.0.0" }.should_not raise_error(ArgumentError)
    lambda { @resource.ip_address "1.1.1.1" }.should_not raise_error(ArgumentError)
    lambda { @resource.ip_address "78.12.34.123" }.should_not raise_error(ArgumentError)
    
    lambda { @resource.ip_address "123.456.789.123" }.should raise_error(ArgumentError)
    lambda { @resource.ip_address "123.456.789.12a" }.should raise_error(ArgumentError)
    lambda { @resource.ip_address "123.4564.789.123" }.should raise_error(ArgumentError)
    lambda { @resource.ip_address :unsupported }.should raise_error(ArgumentError)
  end
end



