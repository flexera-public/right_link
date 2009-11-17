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

require File.join(File.dirname(__FILE__), '..', 'spec_helper')

describe Chef::Resource::PowerShell do

  before(:each) do
    @resource = Chef::Resource::PowerShell.new("testing")
  end

  it "should create a new Chef::Resource::PowerShell" do
      @resource.should be_a_kind_of(Chef::Resource)
      @resource.should be_a_kind_of(Chef::Resource::PowerShell)
    end

  it "should have a name of powershell" do
    @resource.resource_name.should == :powershell
  end

  it "default action should be run" do
    @resource.action == :run
  end

  it "should accept vaild source" do
    @resource.source "write-output \"Running powershell v1.0 script\""
    lambda { @resource.source 123 }.should raise_error(ArgumentError)
  end

  it "should accept vaild parameters" do
    @resource.parameters Chef::Node::Attribute.new(nil, nil, nil)  # mock chef attribute
    lambda { @resource.parameters 123 }.should raise_error(ArgumentError)
  end

  it "should accept vaild cache_dir" do
    @resource.cache_dir File.join(RightScale::RightLinkConfig[:platform].filesystem.temp_dir, "powershell_resource_spec")
    lambda { @resource.cache_dir 123 }.should raise_error(ArgumentError)
  end

  it "should accept vaild audit_id" do
    @resource.audit_id 123
    lambda { @resource.audit_id "not an int" }.should raise_error(ArgumentError)
  end

end
