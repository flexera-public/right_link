#
# Copyright (c) 2013 RightScale Inc
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

require ::File.expand_path(::File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require ::File.expand_path(::File.join(File.dirname(__FILE__), '..', '..', 'instance', 'spec_helper'))

require ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', '..', 'lib', 'clouds', 'cloud'))
require ::File.normalize_path(::File.join(::File.dirname(__FILE__), '..', '..', '..', 'lib', 'clouds', 'clouds', 'cloudstack'))


describe RightScale::Clouds::Cloudstack do

  before(:each) { setup_cloud }
  after(:each)  { teardown_cloud }

  def setup_cloud
    @logger = TestLogger.new()
    @cloud = ::RightScale::Clouds::Cloudstack.new(
      :logger => @logger, 
      :name => "cloudstack",
      :script_path => "/made/up/path")
  end

  def teardown_cloud
    @cloud.finish()
  end

  describe 'dhcp_lease_provider' do
    let(:dhcp_lease_provider_ip) { '1.2.3.4' }
    let(:lease_file_locations) { %w{/var/lib/dhcp/dhclient.eth0.leases /var/lib/dhcp3/dhclient.eth0.leases /var/lib/dhclient/dhclient-eth0.leases /var/lib/dhclient-eth0.leases /var/lib/dhcpcd/dhcpcd-eth0.info} }

    context 'on Linux' do
      before(:each) do 
        @mock_platform = flexmock({:windows? => false})
        flexmock(@cloud, :platform => @mock_platform)
      end
      let(:platform) { flexmock(:platform, :windows? => false) }

      it "should parse lease information" do
        lease_file = lease_file_locations.first
        lease_info = "dhcp-server-identifier #{dhcp_lease_provider_ip}"
        flexmock(@cloud).should_receive(:lease_file_locations).and_return(lease_file_locations)
        flexmock(::File).should_receive(:exist?).with(lease_file).and_return(true)
        flexmock(::File).should_receive(:read).with(lease_file).and_return(lease_info)
        @cloud.dhcp_lease_provider.should == dhcp_lease_provider_ip
      end

      it "should parse lease information on SuSE" do
        lease_file = "/var/lib/dhcpcd/dhcpcd-eth0.info"
        leases = Hash[lease_file_locations.zip [false]*lease_file_locations.length]
        leases[lease_file] = true
        lease_info = "DHCPSID='#{dhcp_lease_provider_ip}'"
        flexmock(@cloud).should_receive(:lease_file_locations).and_return(lease_file_locations)
        leases.each { |file, result| flexmock(::File).should_receive(:exist?).with(file).and_return(result) }
        flexmock(::File).should_receive(:read).with(lease_file).and_return(lease_info)
        @cloud.dhcp_lease_provider.should == dhcp_lease_provider_ip
      end

      it "should fail is no dhcp lease info found" do
        flexmock(::File).should_receive(:exist?).and_return(false)
        expect { @cloud.dhcp_lease_provider }.
          to raise_error(
            ::RightScale::Cloud::CloudError,
            'Cannot determine dhcp lease provider for cloudstack instance')
      end
    end

    context 'on Windows' do
      before(:each) do 
        @mock_platform = flexmock({:windows? => true})
        flexmock(@cloud, :platform => @mock_platform)
      end
      let(:ipconfig_header) do
<<EOF

Windows IP Configuration

   Host Name . . . . . . . . . . . . : MyMachine
   Primary Dns Suffix  . . . . . . . :
   Node Type . . . . . . . . . . . . : Hybrid
   IP Routing Enabled. . . . . . . . : No
   WINS Proxy Enabled. . . . . . . . : No
   DNS Suffix Search List. . . . . . : MyCompany.com

EOF
    end

    let(:ipconfig_dhcp) do
<<EOF
Ethernet adapter Local Area Connection:

   Connection-specific DNS Suffix  . : MyCompany.com
   Description . . . . . . . . . . . : Intel(R) 82567LM-3 Gigabit Network Connection
   Physical Address. . . . . . . . . : 00-11-22-33-44-55
   DHCP Enabled. . . . . . . . . . . : Yes
   Autoconfiguration Enabled . . . . : Yes
   Link-local IPv6 Address . . . . . : 0000::1111:2222:aaaa:bbbb%01(Preferred)
   IPv4 Address. . . . . . . . . . . : 10.10.1.55(Preferred)
   Subnet Mask . . . . . . . . . . . : 255.255.0.0
   Lease Obtained. . . . . . . . . . : Monday, April 22, 2013 9:00:00 AM
   Lease Expires . . . . . . . . . . : Wednesday, April 22, 2015 9:00:00 AM
   Default Gateway . . . . . . . . . : 10.10.0.1
   DHCP Server . . . . . . . . . . . : #{dhcp_lease_provider_ip}
   DHCPv6 IAID . . . . . . . . . . . : 123456789
   DHCPv6 Client DUID. . . . . . . . : 00-11-22-33-44-55-66-77-88-99-AA-BB-CC-DD
   DNS Servers . . . . . . . . . . . : 10.10.1.1
                                       4.3.2.1
                                       4.3.2.2
                                       4.3.2.3
   NetBIOS over Tcpip. . . . . . . . : Enabled

EOF
      end

      let(:ipconfig_full)  { [ipconfig_header, ipconfig_dhcp].join("\n") }
      let(:expected_sleep) { 10 }
      let(:wait_message)   { "ipconfig /all did not contain any DHCP Servers. Retrying in #{expected_sleep} seconds..." }

      it "should parse 'ipconfig /all' output for DHCP Server" do
        flexmock(@cloud).should_receive(:`).with('ipconfig /all').once.and_return(ipconfig_full)
        @cloud.dhcp_lease_provider.should == dhcp_lease_provider_ip
        @cloud.logger.logged[:info].should be_nil
      end

      it "should wait indefinitely until DCHP Server appears in output" do
        mock_cloud = flexmock(@cloud)
        counter = 0
        mock_cloud.should_receive(:`).times(3).with('ipconfig /all').and_return do
          counter += 1
          if counter >= 3
            ipconfig_full
          else
            ipconfig_header
          end
        end
        mock_cloud.should_receive(:sleep).twice.with(expected_sleep).and_return(true)
        @cloud.dhcp_lease_provider.should == dhcp_lease_provider_ip
        @cloud.logger.logged[:info].should == 2.times.map { wait_message }
        counter.should == 3
      end

      it "should timeout after 20 minutes" do
        mock_cloud = flexmock(@cloud)
        counter = 0
        start_time = ::Time.now
        end_time = start_time + 20 * 60 + 1  # 20 minutes, 1 second

        mock_cloud.should_receive(:`).times(3).with('ipconfig /all').and_return do
          counter += 1
          if counter >= 3
            flexmock(::Time).should_receive(:now).and_return(end_time)
          end
          ipconfig_header
        end
        mock_cloud.should_receive(:sleep).times(3).with(expected_sleep).and_return(true)

        expect { @cloud.dhcp_lease_provider.should }.
          to raise_error(
            ::RightScale::Cloud::CloudError,
            'Cannot determine dhcp lease provider for cloudstack instance')
        counter.should == 3
        @cloud.logger.logged[:info].should == 3.times.map { wait_message }
      end
    end
  end
end
