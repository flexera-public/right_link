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

describe Ohai::System, ' plugin cloudstack' do
  let (:fetched_metadata) {
    {
      'public_ipv4' => '1.2.3.4',
      'local_ipv4' => '192.168.0.1',
      'public_hostname' => 'public_hostname',
      'local_hostname' => 'local_hostname'
    }
  }

  let (:fetched_dhcp_lease_provider) {
    '5.6.7.8'
  }

  let (:desired_metadata) {
    {
      'router_ipv4' => '1.2.3.4',
      'local_ipv4' => '192.168.0.1',
      'local_hostname' => 'local_hostname',
      'dhcp_lease_provider_ip' => '5.6.7.8'
    }
  }


  before(:each) do
    temp_dir = Dir.mktmpdir
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(temp_dir)
    # configure ohai for RightScale
    ::Ohai::Config[:hints_path] = [File.join(temp_dir,"ohai","hints")]
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
  end

  it 'create cloudstack attribute if hint file exists and metadata fetch' do
    flexmock(@ohai).should_receive(:hint?).with('cloudstack').and_return({}).once
    flexmock(@ohai).should_receive(:dhcp_lease_provider).and_return(fetched_dhcp_lease_provider).once
    flexmock(@ohai).should_receive(:fetch_metadata).with(fetched_dhcp_lease_provider).and_return(fetched_metadata).once
    @ohai._require_plugin("cloudstack")
    @ohai[:cloudstack].should_not be_nil
    @ohai[:cloudstack].should == desired_metadata
  end

  it 'will not fetch metatada on non-cloudstack' do
    flexmock(@ohai).should_receive(:hint?).with('cloudstack').and_return(nil).once
    flexmock(@ohai).should_not_receive(:fetch_metadata)
    flexmock(@ohai).should_not_receive(:dhcp_lease_provider)
    @ohai._require_plugin("cloudstack")
    @ohai[:cloudstack].should be_nil
  end

  it 'could not connect to dhcp_lease_provider' do
    flexmock(@ohai).should_receive(:hint?).with('cloudstack').and_return({}).once
    flexmock(@ohai).should_not_receive(:fetch_metadata)
    @ohai._require_plugin("cloudstack")
    @ohai[:cloudstack].should be_nil
  end
end
