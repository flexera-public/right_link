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

describe Ohai::System, "plugin rackspace" do
  before(:each) do
    Ohai::Config[:plugin_path] << File.join(File.dirname(__FILE__), '..', 'lib', 'plugins')
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
    @ohai[:network] = {:interfaces => {:eth0 => {"addresses"=> {
          "1.2.3.4"=> {
            "broadcast"=> "67.23.20.255",
            "netmask"=> "255.255.255.0",
            "family"=> "inet"
          },
          "fe80::4240:95ff:fe47:6eed"=> {
            "scope"=> "Link",
            "prefixlen"=> "64",
            "family"=> "inet6"
          },
          "40:40:95:47:6E:ED"=> {
            "family"=> "lladdr"
          }
        }}
      }
    }
        
    @ohai[:network][:interfaces][:eth1] = {:addresses => {  
         "fe80::4240:f5ff:feab:2836" => {
            "scope"=> "Link",
            "prefixlen"=> "64",
            "family"=> "inet6"
          },
          "5.6.7.8"=> {
            "broadcast"=> "10.176.191.255",
            "netmask"=> "255.255.224.0",
            "family"=> "inet"
          },
          "40:40:F5:AB:28:36" => {
            "family"=> "lladdr"
          }
        }}
  end

  describe "!rackspace", :shared => true  do
    it "should NOT create rackspace" do
      @ohai._require_plugin("rackspace")
      @ohai[:rackspace].should be_nil
    end
  end
  
  describe "rackspace", :shared => true do
    
    it "should create rackspace" do
      @ohai._require_plugin("rackspace")
      @ohai[:rackspace].should_not be_nil
    end
    
    it "should have all required attributes" do
      @ohai._require_plugin("rackspace")
      @ohai[:rackspace][:public_ip].should_not be_nil
      @ohai[:rackspace][:private_ip].should_not be_nil
    end

    it "should have correct values for all attributes" do
      @ohai._require_plugin("rackspace")
      @ohai[:rackspace][:public_ip].should == "1.2.3.4"
      @ohai[:rackspace][:private_ip].should == "5.6.7.8"
    end
    
  end

    describe "with rackspace mac and hostname" do
      it_should_behave_like "rackspace"
  
      before(:each) do
        flexmock(IO).should_receive(:select).and_return([[],[1],[]])
        @ohai[:hostname] = "slice74976"
        @ohai[:network][:interfaces][:eth0][:arp] = {"67.23.20.1" => "00:00:0c:07:ac:01"} 
      end
    end
  
    describe "without rackspace mac" do
      it_should_behave_like "!rackspace"
      
      before(:each) do
        @ohai[:hostname] = "slice74976"
        @ohai[:network][:interfaces][:eth0][:arp] = {"169.254.1.0"=>"fe:ff:ff:ff:ff:ff"}
      end
    end

    describe "without rackspace hostname" do
      it_should_behave_like "rackspace"
      
      before(:each) do
        @ohai[:hostname] = "bubba"
        @ohai[:network][:interfaces][:eth0][:arp] = {"67.23.20.1" => "00:00:0c:07:ac:01"} 
      end
    end

end
