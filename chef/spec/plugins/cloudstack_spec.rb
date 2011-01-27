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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper.rb'))

describe Ohai::System, " plugin cloudstack" do
  before(:each) do
    # configure ohai for RightScale
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)

    @cloud = :cloudstack
  end

  context 'when not in the cloudstack cloud' do
    context 'because cloud file refers to another cloud' do
      it_should_behave_like 'cloud file refers to another cloud'
    end
  end

  context 'when in the cloudstack cloud' do
    context 'on a linux instance' do
      before(:each) do
        @ohai[:os] = 'linux'

        lease_file_name = "/var/lib/dhcp3/dhclient.eth0.leases"
        lease_file_content = <<-EOF
        lease {
          interface "eth0";
          fixed-address 111.111.111.2;
          option subnet-mask 255.255.255.0;
          option routers 111.111.111.1;
          option dhcp-lease-time 4294967295;
          option dhcp-message-type 5;
          option domain-name-servers 111.111.111.3;
          option dhcp-server-identifier 111.111.111.3;
          option broadcast-address 111.111.111.255;
          option host-name "2-4-6-8";
          option domain-name "aaabbb.cccddd";
          renew 0 2079/2/5 21:27:55;
          rebind 1 2130/2/20 05:53:24;
          expire 6 2147/2/25 00:42:02;
        }
        EOF

        # mock out the existence of the lease file and it's content
        flexmock(File).should_receive(:exist?).with(lease_file_name).and_return(true)
        flexmock(File).should_receive(:read).with(lease_file_name).and_return(lease_file_content)

        @ohai._require_plugin('linux::cloudstack')
      end

      it 'should find the dhcp server' do
        @ohai[:cloudstack][:dhcp_lease_provider_ip].should == '111.111.111.3'
      end
    end

    shared_examples_for 'on cloudstack' do
      before(:each) do
        @metadata_url = "http://111.111.111.3/latest"
        @userdata_url = "http://111.111.111.3/latest/user-data"
        @root_keys = %w{service-offering availability-zone local-ipv4 local-hostname public-ipv4 public-hostname instance-id}

        @ohai[:cloudstack] = {:dhcp_lease_provider_ip => '111.111.111.3'}

        flexmock(RightScale::CloudUtilities).should_receive(:is_cloud?).and_return(true)
        flexmock(RightScale::CloudUtilities).should_receive(:can_contact_metadata_server?).with("111.111.111.3", 80).and_return(true)
      end

      it_should_behave_like 'can query metadata and user data'
    end
  end
end
