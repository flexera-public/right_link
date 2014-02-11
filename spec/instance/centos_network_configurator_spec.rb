require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance', 'network_configurator'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance', 'network_configurator', 'centos_network_configurator'))

describe RightScale::CentosNetworkConfigurator do
  include FlexMock::ArgumentTypes

  before(:each) do
    subject.logger = TestLogger.new
  end

  describe "Managing SSH Key" do

    let(:public_key) { "some fake public key material" }
    let(:user_ssh_dir) { "/root/.ssh" }
    let(:authorized_keys_file) { "#{user_ssh_dir}/authorized_keys" }

    before(:all) do
      ENV['VS_SSH_PUBLIC_KEY'] = public_key
    end

    it "gets public key string from cloud metadata file" do
      flexmock(::File).should_receive(:join)
      key = subject.get_public_ssh_key_from_metadata()
      key.should == public_key
      subject.logger.logged[:warn].should be_nil
    end

    it "logs a warning if no public key string found in metadata" do
      ENV['VS_SSH_PUBLIC_KEY'] = nil
      flexmock(::File).should_receive(:join)
      subject.get_public_ssh_key_from_metadata()
      subject.logger.logged[:warn].should == ["No public SSH key found in metadata"]
    end


    it "logs a warning if public key is empty string" do
      subject.update_authorized_keys("")
      subject.logger.logged[:warn].should == ["No public SSH key specified -- no modifications to #{authorized_keys_file} made"]
    end

    it "logs a warning if no public key is specified" do
      subject.update_authorized_keys(nil)
      subject.logger.logged[:warn].should == ["No public SSH key specified -- no modifications to #{authorized_keys_file} made"]
    end


    it "appends public key to /root/.ssh/authorized_keys file" do
      flexmock(::FileUtils).should_receive(:mkdir_p).with(user_ssh_dir)
      flexmock(::FileUtils).should_receive(:chmod).with(0600, authorized_keys_file)
      flexmock(subject).should_receive(:read_config_file).and_return("")
      flexmock(subject).should_receive(:append_config_file).with(authorized_keys_file, public_key)
      subject.update_authorized_keys(public_key)
      subject.logger.logged[:info].should == ["Appending public ssh key to #{authorized_keys_file}"]
    end

    it "does nothing if key is already authorized" do
      flexmock(::FileUtils).should_receive(:mkdir_p).with(user_ssh_dir)
      flexmock(::FileUtils).should_receive(:chmod).with(0600, authorized_keys_file)
      flexmock(subject).should_receive(:read_config_file).and_return(public_key)
      subject.update_authorized_keys(public_key)
      subject.logger.logged[:info].should == ["Public ssh key for root already exists in #{authorized_keys_file}"]
    end

    it "does nothing if key is already authorized" do
      flexmock(::FileUtils).should_receive(:mkdir_p).with(user_ssh_dir)
      flexmock(::FileUtils).should_receive(:chmod).with(0600, authorized_keys_file)
      flexmock(::File).should_receive(:exists?).with(authorized_keys_file).and_return(true)
    end

  end

  describe "NAT routing" do

    let(:nat_server_ip) { "10.37.128.195" }
    let(:nat_ranges_string) { "1.2.4.0/24, 1.2.5.0/24, 1.2.6.0/24" }
    let(:nat_ranges) { ["1.2.4.0/24", "1.2.5.0/24", "1.2.6.0/24"] }
    let(:network_cidr) { "8.8.8.0/24" }
    let(:before_routes) { "default via 174.36.32.33 dev eth0  metric 100" }

    let(:routes_file) { "/etc/sysconfig/network-scripts/route-eth0" }

    def after_routes(device, nat_server_ip, network_cidr)
      data=<<-EOH
default via 174.36.32.33 dev eth0  metric 100
      #{network_cidr} via #{nat_server_ip} dev #{device}
      #{nat_server_ip} dev #{device}  scope link
      EOH
      data
    end

    it "missing network route returns false" do
      flexmock(subject).should_receive(:routes_show).and_return(before_routes)
      subject.network_route_exists?(network_cidr, nat_server_ip).should == false
    end

    it "existing network route returns true" do
      flexmock(subject).should_receive(:routes_show).and_return(after_routes("eth0", nat_server_ip, network_cidr))
      subject.network_route_exists?(network_cidr, nat_server_ip).should == true
    end

    it "appends network route" do
      flexmock(subject).should_receive(:runshell).times(1)
      flexmock(subject).should_receive(:routes_show).and_return(before_routes)
      flexmock(subject).should_receive(:update_route_file).and_return(true)
      flexmock(subject).should_receive(:route_device).and_return("eth0")
      subject.network_route_add(network_cidr, nat_server_ip)
    end

    it "does nothing if route already persisted" do
      flexmock(::FileUtils).should_receive(:mkdir_p).with(File.dirname(routes_file))
      flexmock(subject).should_receive(:read_config_file).and_return("#{network_cidr} via #{nat_server_ip}")
      subject.update_route_file(network_cidr, nat_server_ip)
      subject.logger.logged[:info].should == ["Route to #{network_cidr} via #{nat_server_ip} already exists in #{routes_file}"]
    end

    it "appends route to /etc/sysconfig/network-scripts/route-eth0 file" do
      flexmock(::FileUtils).should_receive(:mkdir_p).with(File.dirname(routes_file))
      flexmock(subject).should_receive(:read_config_file).and_return("")
      flexmock(subject).should_receive(:append_config_file).with(routes_file, "#{network_cidr} via #{nat_server_ip}")
      subject.update_route_file(network_cidr, nat_server_ip)
      subject.logger.logged[:info].should == ["Appending #{network_cidr} via #{nat_server_ip} route to #{routes_file}"]
    end

    it "appends all static routes" do
      ENV['RS_NAT_ADDRESS'] = nat_server_ip
      ENV['RS_NAT_RANGES'] = network_cidr

      # network route add
      flexmock(subject).should_receive(:runshell).with("ip route add #{network_cidr} via #{nat_server_ip}").times(1)
      flexmock(subject).should_receive(:routes_show).and_return(before_routes)
      flexmock(subject).should_receive(:update_route_file).times(1)
      flexmock(subject).should_receive(:route_device).and_return("eth0")

      subject.add_static_routes_for_network
    end

  end

    describe "Static IP configuration" do
      before(:each) do
        ENV.delete_if { |k,v| k.start_with?("RS_STATIC_IP") }
      end

      def test_eth_config_data(device, ip, gateway, netmask, nameservers)
        data=<<EOF
# File managed by RightScale
# DO NOT EDIT
DEVICE=#{device}
BOOTPROTO=none
ONBOOT=yes
GATEWAY=#{gateway}
NETMASK=#{netmask}
IPADDR=#{ip}
USERCTL=no
DNS1=#{nameservers[0]}
DNS2=#{nameservers[1]}
PEERDNS=yes
EOF
        data
      end

      let(:device) { "eth0" }
      let(:ip) { "1.2.3.4" }
      let(:gateway) { "1.2.3.1" }
      let(:netmask) { "255.255.255.0" }
      let(:nameservers_string) { "8.8.8.8, 8.8.4.4" }
      let(:nameservers) { [ "8.8.8.8", "8.8.4.4"] }

      let(:resolv_conf_before) {"nameserver 8.8.8.8\nnameserver 8.8.4.4"}
      let(:resolv_conf_after) {"nameserver 8.8.8.8\nnameserver 8.8.4.4"}

      let(:eth_config_data) { test_eth_config_data(device, ip, nil, netmask, nameservers) }
      let(:eth_config_data_w_gateway) { test_eth_config_data(device, ip, gateway, netmask, nameservers) }

      it "parses dns servers to array" do
        subject.parse_array("8.8.8.8,8.8.4.4").should == nameservers
      end

      it "missing nameserver returns false" do
        flexmock(subject).should_receive(:namservers_show).and_return("")
        subject.nameserver_exists?(nameservers[0]).should == false
      end

      it "existing nameserver returns true" do
        flexmock(subject).should_receive(:namservers_show).and_return("nameserver 8.8.8.8\nnameserver 8.8.4.4")
        subject.nameserver_exists?(nameservers[0]).should == true
      end

      it "updates resolv.conf if needed" do
        flexmock(subject).should_receive(:nameserver_exists?).and_return(true)
        flexmock(File).should_receive(:open).times(0)
        subject.nameserver_add("8.8.8.8")
      end

      it "doesn't update resolv.conf if not needed" do
        flexmock(subject).should_receive(:nameserver_exists?).and_return(false)
        flexmock(File).should_receive(:open).times(1)
        subject.nameserver_add("8.8.8.8")
      end

      it "updates ifcfg-eth0" do
        flexmock(subject).should_receive(:runshell).with("ifconfig #{device} #{ip} netmask #{netmask}").times(1)
        flexmock(subject).should_receive(:runshell).with("route add default gw #{gateway}").times(1)
        flexmock(subject).should_receive(:network_route_exists?).and_return(false).times(1)
        flexmock(subject).should_receive(:write_adaptor_config).with(device, eth_config_data_w_gateway)
        subject.configure_network_adaptor(device, ip, netmask, gateway, nameservers)
      end

      it "adds a static IP config for eth0" do
        ENV['RS_STATIC_IP0_ADDR'] = ip
        ENV['RS_STATIC_IP0_NETMASK'] = netmask
        ENV['RS_STATIC_IP0_NAMESERVERS'] = nameservers_string

        flexmock(subject).should_receive(:nameserver_add).times(2)
        flexmock(subject).should_receive(:runshell).with("ifconfig #{device} #{ip} netmask #{netmask}").times(1)
        flexmock(subject).should_receive(:runshell).with("route add default gw #{gateway}").times(0)
        flexmock(subject).should_receive(:network_route_exists?).and_return(false).times(0)
        flexmock(subject).should_receive(:write_adaptor_config).with(device, eth_config_data)
        subject.add_static_ips
      end

      it "supports optional RS_STATIC_IP0_GATEWAY value" do
        ENV['RS_STATIC_IP0_ADDR'] = ip
        ENV['RS_STATIC_IP0_NETMASK'] = netmask
        ENV['RS_STATIC_IP0_NAMESERVERS'] = nameservers_string

        # optional
        ENV['RS_STATIC_IP0_GATEWAY'] = gateway

        flexmock(subject).should_receive(:nameserver_add).times(2)
        flexmock(subject).should_receive(:runshell).with("ifconfig #{device} #{ip} netmask #{netmask}").times(1)
        flexmock(subject).should_receive(:runshell).with("route add default gw #{gateway}").times(1)
        flexmock(subject).should_receive(:network_route_exists?).and_return(false).times(1)
        flexmock(subject).should_receive(:write_adaptor_config).with(device, eth_config_data_w_gateway)
        subject.add_static_ips
      end

      it "supports adding static IP on multiple devices" do
        ifconfig_cmds = []
        eth_configs = []
        10.times do |i|
          ENV["RS_STATIC_IP#{i}_ADDR"] = ip
          ENV["RS_STATIC_IP#{i}_NETMASK"] = netmask
          ENV["RS_STATIC_IP#{i}_NAMESERVERS"] = nameservers_string
          ifconfig_cmds << "ifconfig eth#{i} #{ip} netmask #{netmask}"
          eth_configs <<  test_eth_config_data("eth#{i}", ip, nil, netmask, nameservers)
        end
        flexmock(subject).should_receive(:nameserver_add).times(2*10)
        flexmock(subject).should_receive(:runshell).with(on { |cmd| ifconfig_cmds.include?(cmd) }).times(10)
        flexmock(subject).should_receive(:runshell).with("route add default gw #{gateway}").times(0)
        flexmock(subject).should_receive(:network_route_exists?).and_return(false).times(0)
        flexmock(subject).should_receive(:write_adaptor_config).with(/eth\d/, on { |cfg| !eth_configs.delete(cfg).nil? })
        subject.add_static_ips
      end

    end
end
