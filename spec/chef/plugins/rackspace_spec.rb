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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper.rb'))
require 'tempfile'

describe Ohai::System, ' plugin rackspace' do

  let (:first_network_id) { 'BC764E11172E' }
  let (:second_network_id) { 'BC764E111553' }

  let (:networks_windows) { "#{first_network_id}\n#{second_network_id}" }
  let (:networks_linux) { %Q(#{first_network_id} = "{"label": "private", "broadcast": "10.178.127.255", "ips": [{"ip": "10.178.6.80", "netmask": "255.255.128.0", "enabled": "1", "gateway": null}], "mac": "BC:76:4E:11:17:2E", "dns": ...\n#{second_network_id} = "{"ip6s": [{"ip": "2001:4801:7819:74:be76:4eff:fe11:1553", "netmask": 64, "enabled": "1", "gateway": "fe80::def"}], "label": "public", "broadcast": "162.209.6.255", "ips": [{"ip": "..."') }

  let (:first_network) { '{"label": "private", "broadcast": "10.178.127.255", "ips": [{"ip": "10.178.6.80", "netmask": "255.255.128.0", "enabled": "1", "gateway": null}], "mac": "BC:76:4E:11:17:2E", "dns": ["173.203.4.9", "173.203.4.8"], "routes": [{"route": "10.208.0.0", "netmask": "255.240.0.0", "gateway": "10.178.0.1"}, {"route": "10.176.0.0", "netmask": "255.240.0.0", "gateway": "10.178.0.1"}], "gateway": null}' }
  let (:second_network) { '{"ip6s": [{"ip": "2001:4801:7819:74:be76:4eff:fe11:1553", "netmask": 64, "enabled": "1", "gateway": "fe80::def"}], "label": "public", "broadcast": "162.209.6.255", "ips": [{"ip": "162.209.6.148", "netmask": "255.255.255.0", "enabled": "1", "gateway": "162.209.6.1"}], "mac": "BC:76:4E:11:15:53", "gateway_v6": "fe80::def", "dns": ["173.203.4.9", "173.203.4.8"], "gateway": "162.209.6.1"}' }


  before(:each) do
    temp_dir = Dir.mktmpdir
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(temp_dir)
    # configure ohai for RightScale
    ::Ohai::Config[:hints_path] = [File.join(temp_dir,"ohai","hints")]
    RightScale::OhaiSetup.configure_ohai
    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:hint?).with('rackspace').and_return({}).once
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)

    flexmock(@ohai).should_receive(:xenstore_command).with("read", "vm-data/provider_data/region").and_return([0, "ord", nil]).once
    flexmock(@ohai).should_receive(:hostname).and_return("localhostname")
  end

  it 'populate rackspace node correctly for one private ip' do
    flexmock(@ohai).should_receive(:on_windows?).and_return(false)
    flexmock(@ohai).should_receive(:xenstore_command).with("ls", "vm-data/networking").and_return([0, first_network_id, nil]).once
    flexmock(@ohai).should_receive(:xenstore_command).with("read", "vm-data/networking/#{first_network_id}").and_return([0, first_network, nil]).once

    @ohai._require_plugin("rackspace")
    @ohai[:rackspace].should_not be_nil
    @ohai[:rackspace][:local_ipv4].should == '10.178.6.80'
    @ohai[:rackspace][:public_ipv4].should be_nil
    @ohai[:rackspace][:private_ips].should == ['10.178.6.80']
    @ohai[:rackspace][:public_ips].should == []
  end

  it 'populate rackspace node with ip addresses on linux' do
    flexmock(@ohai).should_receive(:on_windows?).and_return(false)
    flexmock(@ohai).should_receive(:xenstore_command).with("ls", "vm-data/networking").and_return([0, networks_linux, nil]).once
    flexmock(@ohai).should_receive(:xenstore_command).with("read", "vm-data/networking/#{first_network_id}").and_return([0, first_network, nil]).once
    flexmock(@ohai).should_receive(:xenstore_command).with("read", "vm-data/networking/#{second_network_id}").and_return([0, second_network, nil]).once
  
    @ohai._require_plugin("rackspace")
    @ohai[:rackspace].should_not be_nil
    @ohai[:rackspace][:local_ipv4].should == '10.178.6.80'
    @ohai[:rackspace][:public_ipv4].should == '162.209.6.148'
    @ohai[:rackspace][:private_ips].should == ['10.178.6.80']
    @ohai[:rackspace][:public_ips].should == ['162.209.6.148']
  end

  it 'populate rackspace node with ip addresses on windows' do
    flexmock(@ohai).should_receive(:on_windows?).and_return(true)
    flexmock(@ohai).should_receive(:xenstore_command).with("ls", "vm-data/networking").and_return([0, networks_windows, nil]).once
    flexmock(@ohai).should_receive(:xenstore_command).with("read", "vm-data/networking/#{first_network_id}").and_return([0, first_network, nil]).once
    flexmock(@ohai).should_receive(:xenstore_command).with("read", "vm-data/networking/#{second_network_id}").and_return([0, second_network, nil]).once

    @ohai._require_plugin("rackspace")
    @ohai[:rackspace].should_not be_nil
    @ohai[:rackspace][:local_ipv4].should == '10.178.6.80'
    @ohai[:rackspace][:public_ipv4].should == '162.209.6.148'
    @ohai[:rackspace][:private_ips].should == ['10.178.6.80']
    @ohai[:rackspace][:public_ips].should == ['162.209.6.148']
  end
end
