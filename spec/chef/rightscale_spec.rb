#
# Copyright (c) 2009-2011 RightScale Inc
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
require 'flexmock'
 
describe Ohai::System, "plugin rightscale" do
  before(:each) do
    Ohai::Config[:plugin_path] << File.join(File.dirname(__FILE__), '..', '..', 'lib', 'chef', 'plugins')
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
  end
  
  #
  # EC2 Cloud Support
  #
  describe "ec2 with RightScale platform" do
    before(:each) do
      @ohai[:ec2] = Mash.new()
      @ohai[:ec2][:userdata] = "RS_api_url=https:\/\/my.rightscale.com\/api\/inst\/ec2_instances\/c18c07eb8d33456db3d75fe65c56e8bae94d8f59&RS_server=my.rightscale.com&RS_sketchy=sketchy1-12.rightscale.com&RS_token=e668bb0be59d061b8b60f08765902a90"
    end
    
    it "should create rightscale mash" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated].should_not be_nil
    end
    
    it "should create rightscale server mash" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server].should_not be_nil
    end
    
    it "should populate sketchy server attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server]['sketchy'].should == "sketchy1-12.rightscale.com"
    end
    
    it "should populate core server attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server][:core].should == "my.rightscale.com"
    end
    
    it "should populate token attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:token].should == "e668bb0be59d061b8b60f08765902a90"
    end
    
  end

 describe "ec2 without rightscale" do
    before(:each) do
      @ohai[:ec2] = Mash.new()
      @ohai[:ec2][:userdata] = "some other form of userdata"
    end
   
    it "should NOT populate the rightscale data" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale].should be_nil
    end
  end
  
  #
  # Generic Cloud Support
  #
  describe "cloud without rightscale" do
    before(:each) do
      @ohai[:cloud] = Mash.new()
    end
   
    it "should NOT populate the rightscale data" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated].should be_nil
    end
  end

  # Emulate content of metadata file
  class FileMock
    def each(*args)
      yield('RS_syslog=syslog.rightscale.com')
      yield('RS_sketchy=sketchy1-11.rightscale.com')
      yield('RS_server=my.rightscale.com')
      yield('RS_lumberjack=lumberjack.rightscale.com')
      yield('RS_src=dobedobedo')
      yield('RS_token=8bd736d4a8de91b143bcebbb3e513f5f')
      yield('RS_api_url=https://my.rightscale.com/api/inst/ec2_instances/40e9d3956ad2e059f9f4054c6272ce2a38155273')
      yield('RS_token_id=blabla')
      yield('RS_amqp_url=yakityyakyak')
    end
  end
  
  describe "cloud with RightScale platform" do
    before(:each) do
      @ohai[:cloud] = Mash.new()
      @ohai[:cloud][:provider] = "rackspace"
      flexmock(File).should_receive(:exists?).and_return(true)
      flexmock(File).should_receive(:open).and_return(FileMock.new)
    end
    
    it "should create rightscale mash" do     
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated].should_not be_nil
    end
    
    it "should create rightscale server mash" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server].should_not be_nil
    end
         
    it "should populate sketchy server attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server][:sketchy].should == "sketchy1-11.rightscale.com"
    end

    it "should populate core server attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server][:core].should == "my.rightscale.com"
    end

    it "should populate syslog server attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server][:syslog].should == "syslog.rightscale.com"
    end

    it "should populate lumberjack server attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:server][:lumberjack].should == "lumberjack.rightscale.com"
    end

    it "should populate token attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:token].should == "8bd736d4a8de91b143bcebbb3e513f5f"
    end
    
    it "should populate api_url attribute" do
      @ohai._require_plugin("rightscale")
      @ohai[:rightscale_deprecated][:api_url].should == "https://my.rightscale.com/api/inst/ec2_instances/40e9d3956ad2e059f9f4054c6272ce2a38155273"
    end
    
  end
  
end