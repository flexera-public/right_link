#
# Copyright (c) 2014 RightScale Inc
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

describe Ohai::System, 'plugin vsphere' do

  before(:each) do
    temp_dir = Dir.mktmpdir
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(temp_dir)
    # configure ohai for RightScale
    ::Ohai::Config[:hints_path] = [File.join(temp_dir,"ohai","hints")]
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
    @vsphere = get_plugin("vsphere", @ohai)
    @network = {
        :interfaces => {
            :lo   => { :flags => ["LOOPBACK"] },
            :eth0 => { :flags => [], :addresses => { "50.23.101.210" => { 'family' => 'inet' } } },
            :eth1 => { :flags => [], :addresses => { "192.168.0.1" => { 'family' => 'inet' } } }
        }
    }
  end

  it 'create vsphere if hint file exists' do
    flexmock(@vsphere).should_receive(:hint?).with('vsphere').and_return({}).once
    flexmock(@vsphere).should_receive(:network).and_return(@network)
    @vsphere.run
    @ohai[:vsphere].should_not be_nil
  end

  it "not create vsphere if hint file doesn't exists" do
    flexmock(@vsphere).should_receive(:hint?).with('vsphere').and_return(nil).once
    @vsphere.run
    @ohai[:vsphere].should be_nil
  end

  it 'populate vsphere node with required attributes' do
    flexmock(@vsphere).should_receive(:hint?).with('vsphere').and_return({}).once
    flexmock(@vsphere).should_receive(:network).and_return(@network)
    @vsphere.run
    @ohai[:vsphere]['local_ipv4'] = '50.23.101.210'
    @ohai[:vsphere]['public_ipv4'] = '192.168.0.1'
    @ohai[:vsphere]['private_ips'] = ['50.23.101.210']
    @ohai[:vsphere]['public_ips'] = ['192.168.0.1']
  end
end
