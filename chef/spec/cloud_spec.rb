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

require File.join(File.dirname(__FILE__), 'spec_helper.rb')

describe Ohai::System, "plugin cloud" do
  before(:each) do
    Ohai::Config[:plugin_path] << File.join(File.dirname(__FILE__), '..', 'lib', 'plugins')
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
  end

  describe "no cloud" do
    it "should NOT populate the cloud data" do
      @ohai[:ec2] = nil
      @ohai[:rackspace] = nil
      @ohai._require_plugin("cloud")
      @ohai[:cloud].should be_nil
    end
  end
  
  describe "with EC2" do
    before(:each) do
      @ohai[:ec2] = Mash.new()
    end  
    
    it "should populate cloud public ip" do
      @ohai[:ec2]['public_ipv4'] = "174.129.150.8"
      @ohai._require_plugin("cloud")
      @ohai[:cloud][:public_ip][0].should == @ohai[:ec2]['public_ipv4']
    end

    it "should populate cloud private ip" do
      @ohai[:ec2]['local_ipv4'] = "10.252.42.149"
      @ohai._require_plugin("cloud")
      @ohai[:cloud][:private_ip][0].should == @ohai[:ec2]['local_ipv4']
    end
    
    it "should populate cloud provider" do
      @ohai._require_plugin("cloud")
      @ohai[:cloud][:provider].should == "ec2"
    end
  end
  
  describe "with rackspace" do
    before(:each) do
      @ohai[:rackspace] = Mash.new()
    end  
    
    it "should populate cloud public ip" do
      @ohai[:rackspace]['public_ip'] = "174.129.150.8"
      @ohai._require_plugin("cloud")
      @ohai[:cloud][:public_ip][0].should == @ohai[:rackspace][:public_ip]
    end
        
    it "should populate cloud private ip" do
      @ohai[:rackspace]['private_ip'] = "10.252.42.149"
      @ohai._require_plugin("cloud")
      @ohai[:cloud][:private_ip][0].should == @ohai[:rackspace][:private_ip]
    end
        
    it "should populate cloud provider" do
      @ohai._require_plugin("cloud")
      @ohai[:cloud][:provider].should == "rackspace"
    end
  end
  
end
