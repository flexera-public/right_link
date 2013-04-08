self.instance_eval do
  def abbreviation *args; end
  def option *args; true; end
  def default_option *args; end
  def metadata_source *args; end
  def extend_cloud *args; end
end

require File.join(File.dirname(__FILE__), '..', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'clouds', 'clouds', 'cloudstack')

describe 'dhcp_lease_provider_ip' do
  def platform
    flexmock(:windows? => false)
  end
  it "should parse lease information" do
    dhcp_lease_provider_ip = "1.1.1.1"
    lease_file = "/var/lib/dhcp/dhclient.eth0.leases"
    lease_info = "dhcp-server-identifier #{dhcp_lease_provider_ip}"
    flexmock(File).should_receive(:exist?).with(lease_file).and_return(true)
    flexmock(File).should_receive(:read).with(lease_file).and_return(lease_info)
    dhcp_lease_provider.should == dhcp_lease_provider_ip
  end

  it "should parse lease information on SuSE" do
    dhcp_lease_provider_ip = "1.1.1.1"
    lease_file = "/var/lib/dhcpcd/dhcpcd-eth0.info"
    lease_files = %w{/var/lib/dhcp/dhclient.eth0.leases /var/lib/dhcp3/dhclient.eth0.leases /var/lib/dhclient/dhclient-eth0.leases /var/lib/dhclient-eth0.leases /var/lib/dhcpcd/dhcpcd-eth0.info}
    leases = Hash[lease_files.zip [false]*lease_files.length]
    leases[lease_file] = true
    lease_info = "DHCPSID='#{dhcp_lease_provider_ip}'"
    leases.each { |file, result| flexmock(File).should_receive(:exist?).with(file).and_return(result) }
    flexmock(File).should_receive(:read).with(lease_file).and_return(lease_info)
    dhcp_lease_provider.should == dhcp_lease_provider_ip
  end
  
  it "should fail is no dhcp lease info found" do
    flexmock(File).should_receive(:exist?).and_return(false)
    lambda {
      dhcp_lease_provider 
    }.should raise_error(RuntimeError, "Cannot determine dhcp lease provider for cloudstack instance")
  end

  it "should have test for windows case" do
    pending
  end
end
