#
# Copyright (c) 2011 RightScale Inc
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

require File.expand_path('../spec_helper', __FILE__)
require 'tempfile'

describe Ohai::System, ' plugin missing_cloud' do

  before(:each) do
    temp_dir = Dir.mktmpdir
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(temp_dir)
    # configure ohai for RightScale
    ::Ohai::Config[:hints_path] = [File.join(temp_dir,"ohai","hints")]
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
    @ohai.data[:cloud] = Mash.new
    @ohai.data[:cloud][:public_ips] = Array.new
    @ohai.data[:cloud][:private_ips] = Array.new
  end

  context 'on cloudstack' do
    before(:each) do
      @ohai.data[:cloudstack] = Mash.new()
    end

    it 'should populate cloud provider' do
      get_plugin("missing_cloud", @ohai).run
      @ohai[:cloud][:provider].should == 'cloudstack'
    end

    it 'should populate cloud public ip' do
      @ohai.data[:cloudstack][:public_ipv4] = "1.1.1.1"
      get_plugin("missing_cloud", @ohai).run

      @ohai[:cloud][:public_ipv4].should ==  "1.1.1.1"
      @ohai[:cloud][:public_ips].first.should ==  "1.1.1.1"
    end

    it 'should not populate cloud public ip if it is nul' do
      @ohai.data[:cloudstack][:public_ipv4] = nil
      get_plugin("missing_cloud", @ohai).run

      @ohai[:cloud][:public_ipv4].should be_nil
      @ohai[:cloud][:public_ips].should ==  []
    end


    it 'should populate cloud private ip' do
      @ohai[:cloudstack][:local_ipv4] = "10.252.252.10"
      get_plugin("missing_cloud", @ohai).run
      @ohai[:cloud][:local_ipv4].should == "10.252.252.10"
      @ohai[:cloud][:private_ips].first.should == "10.252.252.10"
    end

    it 'should not populate cloud private ip if it is nul' do
      @ohai[:cloudstack][:local_ipv4] = nil
      get_plugin("missing_cloud", @ohai).run

      @ohai[:cloud][:local_ipv4].should be_nil
      @ohai[:cloud][:private_ips].should ==  []
    end


    it 'should populate cloud public hostname' do
      @ohai.data[:cloudstack][:public_hostname] = "my_public_hostname"
      get_plugin("missing_cloud", @ohai).run
      @ohai[:cloud][:public_hostname].should == "my_public_hostname"
    end

    it 'should populate cloud local hostname' do
      @ohai.data[:cloudstack][:local_hostname] = "my_local_hostname"
      get_plugin("missing_cloud", @ohai).run
      @ohai[:cloud][:local_hostname].should == "my_local_hostname"
    end

  end

  context 'on softlayer' do
    before(:each) do
      @ohai.data[:softlayer] = Mash.new{}
    end

    it 'should populate cloud provider' do
      get_plugin("missing_cloud", @ohai).run
      @ohai[:cloud][:provider].should == 'softlayer'
    end

  end

  context 'on vsphere' do
    before(:each) do
      @ohai.data[:vsphere] = Mash.new{}
    end

    it 'should populate cloud provider' do
      get_plugin("missing_cloud", @ohai).run
      @ohai[:cloud][:provider].should == 'vsphere'
    end

  end

end
