#
# Copyright (c) 2010-2014 RightScale Inc
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

require 'open-uri'
require 'socket'

module ::Ohai::Mixin::RightLink

  module CloudUtilities

    IP_ADDRESS_REGEX = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/

    DEFAULT_WHATS_MY_IP_HOST_NAME = 'eip-us-east.rightscale.com'
    DEFAULT_WHATS_MY_IP_TIMEOUT = 10 * 60
    DEFAULT_WHATS_MY_IP_RETRY_DELAY = 5

    # Queries a whats-my-ip service for the public IP address of this instance.
    # can query either for an expected IP or for any IP which is voted by majority
    # (or unanimously). this is no guarantee that an instance actually has a public
    # IP individually assigned to it as a private cloud instance will still appear
    # to have it's router's public IP as it's own address.
    #
    # === Parameters
    # options[:expected_ip](String):: expected IP address or nil (no DNS names)
    # options[:unanimous][TrueClass|FalseClass]:: true if vote must be unanimous, false for simple majority of all responders
    # options[:host_name](String):: host name for whats-my-ip query or DEFAULT_WHATS_MY_IP_HOST_NAME
    # options[:timeout][Fixnum]:: timeout in seconds or DEFAULT_WHATS_MY_IP_TIMEOUT
    # options[:retry_delay][Fixnum]:: retry delay in seconds or DEFAULT_WHATS_MY_IP_RETRY_DELAY
    #
    # === Return
    # public_ip(String):: the consensus public IP for this instance or nil
    def self.query_whats_my_ip(options={})
      expected_ip = options[:expected_ip]
      raise ArgumentError.new("expected_ip is invalid") if expected_ip && !(expected_ip =~ IP_ADDRESS_REGEX)
      unanimous = options[:unanimous] || false
      host_name = options[:host_name] || DEFAULT_WHATS_MY_IP_HOST_NAME
      timeout = options[:timeout] || DEFAULT_WHATS_MY_IP_TIMEOUT
      retry_delay = options[:retry_delay] || DEFAULT_WHATS_MY_IP_RETRY_DELAY

      ::Ohai::Log.debug( expected_ip ? "Waiting for IP=#{expected_ip}" : "Waiting for any IP to converge." )

      # attempt to dig some hosts.
      hosts = `dig +short #{host_name}`.strip.split
      if hosts.empty?
        ::Ohai::Log.debug("No hosts to poll for IP from #{host_name}.")
      else
        # a little randomization avoids hitting the same hosts from each
        # instance since there is no guarantee that the hosts are returned in
        # random order.
        hosts = hosts.sort { (rand(2) * 2) - 1 }

        message = ["Using these hosts to check the IP:"]
        hosts.each { |host| message << "  #{host}" }
        message << "-------------------------"
        ::Ohai::Log.debug(message.join("\n"))

        unanimity = hosts.count
        required_votes = unanimous ? unanimity : (1 + unanimity / 2)
        ::Ohai::Log.debug("Required votes = #{required_votes}/#{unanimity}")
        end_time = Time.now + timeout
        loop do
          reported_ips_to_voters = {}
          address_to_hosts = {}
          hosts.each do |host|
            address = `curl --max-time 1 -S -s http://#{host}/ip/mine`.strip
            ::Ohai::Log.debug("Host=#{host} reports IP=#{address}")
            address_to_hosts[address] ||= []
            address_to_hosts[address] << host
            if expected_ip
              vote = (address_to_hosts[expected_ip] || []).count
              popular_address = expected_ip
            else
              popular_address = nil
              vote = 0
              address_to_hosts.each do |address, hosts|
                if hosts.count > vote
                  vote = hosts.count
                  popular_address = address
                end
              end
            end
            if vote >= required_votes
              ::Ohai::Log.debug("IP=#{popular_address} has the required vote count of #{required_votes}.")
              return popular_address
            end
          end

          # go around again, if possible.
          now_time = Time.now
          break if now_time >= end_time
          retry_delay = [retry_delay, end_time - now_time].min.to_i
          ::Ohai::Log.debug("Sleeping for #{retry_delay} seconds...")
          sleep retry_delay
          retry_delay = [retry_delay * 2, 60].min  # a little backoff helps when launching thousands
        end
        ::Ohai::Log.debug("Never got the required vote count of #{required_votes}/#{unanimity} after #{timeout} seconds; public IP did not converge.")
        return nil
      end
    end

    def private_ipv4?(ip)
      regexp = /\A(10\.|192\.168\.|172\.1[6789]\.|172\.2.\.|172\.3[01]\.)/
      ip =~ regexp
    end

    def ips(network)
      @ips ||= [].tap do |ips|
        network[:interfaces].each_value do |interface|
          next if interface.fetch(:flags, {}).include?("LOOPBACK")
          addresses = interface[:addresses].find { |key, item| item['family'] == 'inet' }
          ips << addresses.first
        end
      end
    end

    def public_ips(network)
      @public_ips ||= ips(network).reject { |ip| private_ipv4?(ip) }
    end

    def private_ips(network)
      @private_ips ||= ips(network).select { |ip| private_ipv4?(ip) }
    end
  end


  module AzureMetadata

    def query_whats_my_ip(opts)
      CloudUtilities::query_whats_my_ip(opts)
    end

    def tcp_test_winrm(ip_addr, port, &block)
      socket = TCPSocket.new(hostname, port)
      ::Ohai::Log.debug("WinRM accepting connections on #{fqdn}")
      yield if block
      true
    rescue SocketError
      sleep 2
      false
    rescue Errno::ETIMEDOUT
      false
    rescue Errno::EPERM
      false
    rescue Errno::ECONNREFUSED
      sleep 2
      false
    rescue Errno::EHOSTUNREACH
      sleep 2
      false
    rescue Errno::ENETUNREACH
      sleep 2
      false
    ensure
      socket && socket.close
    end

    def tcp_test_ssh(fqdn, sshport, &block)
      socket = TCPSocket.new(fqdn, sshport)
      readable = IO.select([socket], nil, nil, 5)
      if readable
        ::Ohai::Log.debug("sshd accepting connections on #{fqdn}, banner is #{socket.gets}")
        yield if block
        true
      else
        false
      end
    rescue SocketError
      sleep 2
      false
    rescue Errno::ETIMEDOUT
      false
    rescue Errno::EPERM
      false
    rescue Errno::ECONNREFUSED
      sleep 2
      false
    rescue Errno::EHOSTUNREACH
      sleep 2
      false
    ensure
      socket && socket.close
    end
  end

  module DirMetadata
    # Fetch metadata form dir (recursevly).
    # each file name is a key and value it's content
    def self.fetch_from_dir(metadata_dir, metadata = {})
      raise "Meta-data dir does not exist: #{metadata_dir}" unless File.directory?(metadata_dir)
      ::Ohai::Log.debug('Fetching from meta-data dir: #{metadata_dir}')
      metadata = {}
      Dir.foreach(metadata_dir) do |name|
        next if name =='.' || name  == '..'
        metadata_file = File.join(metadata_dir,name)
        key = name.gsub(/\-/,'_')
        if File.directory?(metadata_file)
          metadata[key] = fetch_from_dir(metadata_file, {})
        else
          value = File.read(metadata_file)
          metadata[key] = value
        end
      end
      metadata
    end

    # Get default RightLink meta-data dir location
    def rightlink_metadata_dir
      var_dir = File.join( RUBY_PLATFORM =~ /mswin|mingw|windows/ ? [ENV['ProgramData'],'RightScale'] : ['/', 'var'] )
      metadata_dir = File.join(var_dir, 'spool','cloud','meta-data')
      metadata_dir
    end

    # Fetch metadata
    def fetch_metadata(metadata_dir)
      ::Ohai::Log.debug('Fetching metadata')
      metadata = DirMetadata::fetch_from_dir(metadata_dir)
      ::Ohai::Log.debug("Fetched metadata: #{metadata.inspect}")
      metadata
    rescue
      ::Ohai::Log.error("Fetching metadata failed: #{$!}")
      false
    end

    # Searches for a file containing dhcp lease information.
    def dhcp_lease_provider
      if RUBY_PLATFORM =~ /mswin|mingw|windows/
        timeout = Time.now + 20 * 60  # 20 minutes
        while Time.now < timeout
          ipconfig_data = `ipconfig /all`
          match_result = ipconfig_data.match(/DHCP Server.*\: (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/)
          unless match_result.nil? || match_result[1].nil?
            return match_result[1]
          end
          # it may take time to resolve the DHCP Server for this instance, so sleepy wait.
          ::Ohai::Log.debug("ipconfig /all did not contain any DHCP Servers. Retrying in 10 seconds...")
          sleep 10
        end
      else
        leases_file = %w{/var/lib/dhcp/dhclient.eth0.leases /var/lib/dhcp3/dhclient.eth0.leases /var/lib/dhclient/dhclient-eth0.leases /var/lib/dhclient-eth0.leases /var/lib/dhcpcd/dhcpcd-eth0.info}.find{|dhcpconfig| File.exist?(dhcpconfig)}
        unless leases_file.nil?
          lease_file_content = File.read(leases_file)

          dhcp_lease_provider_ip = lease_file_content[/DHCPSID='(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'/, 1]
          return dhcp_lease_provider_ip unless dhcp_lease_provider_ip.nil?

          # leases are appended to the lease file, so to get the appropriate dhcp lease provider, we must grab
          # the info from the last lease entry.
          #
          # reverse the content and reverse the regex to find the dhcp lease provider from the last lease entry
          lease_file_content.reverse!
          dhcp_lease_provider_ip = lease_file_content[/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) reifitnedi-revres-pchd/, 1]
          return dhcp_lease_provider_ip.reverse unless dhcp_lease_provider_ip.nil?
        end
      end
      # no known defaults so we must fail at this point.
      raise "Cannot determine dhcp lease provider for cloudstack instance"
    end

  end
end
