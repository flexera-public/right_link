require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance', 'network_configurator'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance', 'network_configurator', 'windows_network_configurator'))

describe RightScale::WindowsNetworkConfigurator do
  include FlexMock::ArgumentTypes

  before(:each) do
    subject.logger = TestLogger.new
  end

  describe "Static IP configuration" do
    before(:each) do
      ENV.delete_if { |k,v| k.start_with?("RS_IP") }
      ENV['RS_IP0_NAMESERVERS'] = '8.8.8.8,8.8.4.4'
    end

    let(:device) { "Local Area Connection" }
    let(:mac) { "MAC:MAC:MAC" }
    let(:ip) { "1.2.3.4" }
    let(:gateway) { "1.2.3.1" }
    let(:netmask) { "255.255.255.0" }
    let(:nameservers_output) { "8.8.8.8" }

    it "adds a primary namserver" do
      flexmock(subject).should_receive(:runshell).with("netsh interface ipv4 set dnsserver name=#{device.inspect} source=static addr=8.8.8.8 register=primary validate=no")
      flexmock(subject).should_receive(:nameserver_exists?).and_return(false)
      subject.add_nameserver_to_device(device.inspect, "8.8.8.8", 1)
    end

    it "adds a secondary nanamserver" do
      flexmock(subject).should_receive(:runshell).with("netsh interface ipv4 add dnsserver name=#{device.inspect} addr=8.8.8.8 index=2 validate=no")
      flexmock(subject).should_receive(:nameserver_exists?).and_return(false)
      subject.add_nameserver_to_device(device.inspect, "8.8.8.8", 2)
    end


    it "adds a static IP config for Local Area Network" do
      cmd = "netsh interface ip set address name=#{device} source=static addr=#{ip} mask=#{netmask} gateway=none"
      ENV['RS_IP0_ADDR'] = ip
      ENV['RS_IP0_NETMASK'] = netmask
      ENV['RS_IP0_MAC'] = mac

      flexmock(subject).should_receive(:configured_nameservers).and_return("8.8.8.8 4.4.4.4")
      flexmock(subject).should_receive(:add_nameserver_to_device).times(0)
      flexmock(subject).should_receive(:device_name_from_mac).with(mac).and_return(device)
      flexmock(subject).should_receive(:configure_network_adaptor).times(1)
      flexmock(subject).should_receive(:network_device_name).and_return(device)
      flexmock(subject).should_receive(:runshell).with(cmd)
      flexmock(subject).should_receive(:wait_for_configuration_appliance)
      subject.add_static_ips
    end

    it "supports optional RS_IP0_GATEWAY value" do
      ENV['RS_IP0_ADDR'] = ip
      ENV['RS_IP0_NETMASK'] = netmask
      ENV['RS_IP0_MAC'] = mac

      # optional
      ENV['RS_IP0_GATEWAY'] = gateway

      cmd = "netsh interface ip set address name=#{device.inspect} source=static addr=#{ip} mask=#{netmask} gateway="
      cmd += gateway ? "#{gateway} gwmetric=1" : "none"

      flexmock(subject).should_receive(:configured_nameservers).and_return(nameservers_output)
      flexmock(subject).should_receive(:add_nameserver_to_device).times(2)
      flexmock(subject).should_receive(:device_name_from_mac).with(mac).and_return(device)
      flexmock(subject).should_receive(:runshell).with(cmd)
      flexmock(subject).should_receive(:network_device_name).and_return(device)
      flexmock(subject).should_receive(:wait_for_configuration_appliance)
      subject.add_static_ips
    end

    it "supports adding static IP on multiple devices" do
      netsh_cmds = []
      flexmock(subject).should_receive(:network_device_name).and_return(device)
      subject.os_net_devices.each_with_index do |device, i|
        ENV["RS_IP#{i}_ADDR"] = ip
        ENV["RS_IP#{i}_NETMASK"] = netmask
        ENV["RS_IP#{i}_MAC"] = "#{mac}#{i}"
        cmd = "netsh interface ip set address name=#{device.inspect} source=static addr=#{ip} mask=#{netmask} gateway=none"
        netsh_cmds << cmd
      end

      flexmock(subject).should_receive(:configured_nameservers).and_return(nameservers_output)
      flexmock(subject).should_receive(:add_nameserver_to_device).times(2)

      subject.define_singleton_method(:device_name_from_mac) do |mac_addr|
        index = mac_addr.sub(/\D+/, '').to_i
        os_net_devices[index]
      end
      flexmock(subject).should_receive(:runshell).with(on { |cmd| !netsh_cmds.delete(cmd).nil? }).times(10)
      flexmock(subject).should_receive(:wait_for_configuration_appliance)
      subject.add_static_ips
    end

    it "waits for configuration appliance" do
      cmd = "netsh interface ip set address name=#{device.inspect} source=static addr=#{ip} mask=#{netmask} gateway=none"
      ENV['RS_IP0_ADDR'] = ip
      ENV['RS_IP0_NETMASK'] = netmask
      ENV['RS_IP0_MAC'] = mac

      flexmock(subject).should_receive(:configured_nameservers).and_return(nameservers_output)
      flexmock(subject).should_receive(:add_nameserver_to_device).times(2)
      flexmock(subject).should_receive(:device_name_from_mac).with(mac).and_return(device)
      flexmock(subject).should_receive(:runshell).with(cmd)
      flexmock(subject).should_receive(:network_device_name).and_return(device)
      flexmock(subject).should_receive(:get_device_ip).with(device.inspect).times(2).and_return(nil, ip)
      flexmock(subject).should_receive(:sleep).with(2).at_least.once
      subject.add_static_ips
    end
  end

  describe 'NAT routing' do
    let(:nat_server_ip) { "10.37.128.195" }
    let(:nat_ranges_string) { "1.2.4.0/24, 1.2.5.0/24, 1.2.6.0/24" }
    let(:nat_ranges) { ["1.2.4.0/24", "1.2.5.0/24", "1.2.6.0/24"] }
    let(:network_cidr) { "8.8.8.0/24" }

    it "appends network route" do
      network, mask = subject.cidr_to_netmask(network_cidr)

      flexmock(subject).should_receive(:network_route_exists?).and_return(false)
      cmd = "route -p ADD #{network} MASK #{mask} #{nat_server_ip}"
      flexmock(subject).should_receive(:runshell).with(cmd)

      subject.network_route_add(network_cidr, nat_server_ip)
    end

    it "appends all static routes" do
      ENV['RS_ROUTE0'] = nat_server_ip+":"+nat_ranges[0]
      ENV['RS_ROUTE1'] = nat_server_ip+":"+nat_ranges[1]
      ENV['RS_ROUTE2'] = nat_server_ip+":"+nat_ranges[2]

      # network route add
      flexmock(subject).should_receive(:network_route_exists?).and_return(false)
      cmd = /route -p ADD \d+.\d+.\d+.\d+ MASK \d+.\d+.\d+.\d+ #{nat_server_ip}/
        flexmock(subject).should_receive(:runshell).with(cmd).times(nat_ranges.length)
      subject.add_static_routes_for_network
    end
  end
end
