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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

  describe Chef::Resource::Powershell do

    before(:each) do
      @resource = Chef::Resource::Powershell.new("testing")
    end

    it "should create a new Chef::Resource::Powershell" do
      @resource.should be_a_kind_of(Chef::Resource)
      @resource.should be_a_kind_of(Chef::Resource::Powershell)
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

    it "should accept vaild source_path" do
      @resource.source_path "c:/temp/test.ps1"
      lambda { @resource.source_path 123 }.should raise_error(ArgumentError)
    end

    it "should accept vaild parameters" do
      # FIX: use of Chef::Node::Attribute is deprecated but still supported for now.
      # (normal, default, override, automatic, state=[])
      @resource.parameters Chef::Node::Attribute.new({"TEST_X" => "x", "TEST_Y" => "y"}, nil, nil, nil)

      @resource.parameters("TEST_X" => "x", "TEST_Y" => "y")
      lambda { @resource.parameters 123 }.should raise_error(TypeError)
    end

    it "should accept valid returns" do
      @resource.returns 77
      lambda { @resource.returns "bogus" }.should raise_error(ArgumentError)
    end

  end

end # if windows?
