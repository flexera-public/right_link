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

require 'open-uri'
require 'socket'

module RightScale

  class CloudUtilities

    IP_ADDRESS_REGEX = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/

    DEFAULT_WHATS_MY_IP_HOST_NAME = 'eip-us-east.rightscale.com'
    DEFAULT_WHATS_MY_IP_TIMEOUT = 10 * 60
    DEFAULT_WHATS_MY_IP_RETRY_DELAY = 5

    # Does an interface have the given mac address?
    #
    # === Parameters
    # ohai(Mash):: ohai state
    # mac(String):: MAC address to find
    #
    # === Return
    # (Boolean):: true if there is an interface with the given mac address
    def self.has_mac?(ohai, mac)
      !!ohai[:network][:interfaces].values.detect { |iface| !iface[:arp].nil? && iface[:arp].value?(mac) }
    end

    # Attempt to connect to the given address on the given port as a quick verification
    # that the metadata service is available.
    #
    # === Parameters
    # addr(String):: address of the metadata service
    # port(Number):: port of the metadata service
    # timeout(Number)::Optional - time to wait for a response
    #
    # === Return
    # connected(Boolean):: true if a connection could be made, false otherwise
    def self.can_contact_metadata_server?(addr, port, timeout=2)
      t = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
      saddr = Socket.pack_sockaddr_in(port, addr)
      connected = false

      begin
        t.connect_nonblock(saddr)
      rescue Errno::EINPROGRESS
        r, w, e = IO::select(nil, [t], nil, timeout)
        if !w.nil?
          connected = true
        else
          begin
            t.connect_nonblock(saddr)
          rescue Errno::EISCONN
            t.close
            connected = true
          rescue SystemCallError
          end
        end
      rescue SystemCallError
      end

      connected
    end

    # Finds the first ip address for a given interface in the ohai mash
    #
    # === Parameters
    # ohai(Mash):: ohai state
    # interface(Symbol):: symbol of the interface (:eth0, :eth1, ...)
    #
    # === Return
    # address(String|nil):: ip address associated with the given interface, nil if interface could not be found
    def self.ip_for_interface(ohai, interface, family='inet')
      address = nil
      if ohai[:network] != nil &&
         ohai[:network][:interfaces] != nil &&
         ohai[:network][:interfaces][interface] != nil &&
         ohai[:network][:interfaces][interface][:addresses] != nil

        addresses = ohai[:network][:interfaces][interface][:addresses].find { |key, item| item['family'] == family }
        address = addresses.first unless addresses.nil?
      end

      address
    end

    def self.ipv6_for_interface(ohai, interface)
      ip_for_interface(ohai, interface, 'inet6')
    end


    # Finds the first ip address that matches a given connection type (private|public)
    #
    # === Parameters
    # ohai(Mash):: ohai state
    # connection_type(Symbol):: either 'public' or 'private'
    #
    # === Return
    # address(String|nil):: ip address associated with the given interface, nil if interface could not be found
    def self.ip_for_windows_interface(ohai, connection_type)
      address = nil

      # find the right interface
      if ohai[:network] != nil &&
         ohai[:network][:interfaces] != nil
        interface = ohai[:network][:interfaces].values.find do |item|
          !(item.nil? || item[:instance].nil?) && item[:instance][:net_connection_id] == connection_type
        end

        # grab the ip if there is one
        if interface != nil &&
           interface["configuration"] != nil &&
           interface["configuration"]["ip_address"] != nil
          address = interface["configuration"]["ip_address"].first
        end
      end

      address
    end

    # Splits data on the given splitter character and merges to the given hash.
    #
    # === Parameters
    # data(String):: raw data
    # splitter(String):: splitter character
    # hash(Hash):: hash to merge
    # name_value_delimiter(String):: name/value delimiter (defaults to '=')
    #
    # === Return
    # hash(Hash):: merged hash result
    def self.split_metadata(data, splitter, hash, name_value_delimiter = '=')
      data.split(splitter).each do |pair|
        name, value = pair.split(name_value_delimiter, 2)
        hash[name.strip] = value.strip if name && value
      end
      hash
    end

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
    # options[:logger](Logger):: logger or defaults to null logger
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
      logger = options[:logger] || Logger.new(::RightScale::Platform::Shell::NULL_OUTPUT_NAME)
      timeout = options[:timeout] || DEFAULT_WHATS_MY_IP_TIMEOUT
      retry_delay = options[:retry_delay] || DEFAULT_WHATS_MY_IP_RETRY_DELAY

      if expected_ip
        logger.info("Waiting for IP=#{expected_ip}")
      else
        logger.info("Waiting for any IP to converge.")
      end

      # attempt to dig some hosts.
      hosts = `dig +short #{host_name}`.strip.split
      if hosts.empty?
        logger.info("No hosts to poll for IP from #{host_name}.")
      else
        # a little randomization avoids hitting the same hosts from each
        # instance since there is no guarantee that the hosts are returned in
        # random order.
        hosts = hosts.sort { (rand(2) * 2) - 1 }
        if logger.debug?
          message = ["Using these hosts to check the IP:"]
          hosts.each { |host| message << "  #{host}" }
          message << "-------------------------"
          logger.debug(message.join("\n"))
        end

        unanimity = hosts.count
        required_votes = unanimous ? unanimity : (1 + unanimity / 2)
        logger.info("Required votes = #{required_votes}/#{unanimity}")
        end_time = Time.now + timeout
        loop do
          reported_ips_to_voters = {}
          address_to_hosts = {}
          hosts.each do |host|
            address = `curl --max-time 1 -S -s http://#{host}/ip/mine`.strip
            logger.debug("Host=#{host} reports IP=#{address}")
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
              logger.info("IP=#{popular_address} has the required vote count of #{required_votes}.")
              return popular_address
            end
          end

          # go around again, if possible.
          now_time = Time.now
          break if now_time >= end_time
          retry_delay = [retry_delay, end_time - now_time].min.to_i
          logger.debug("Sleeping for #{retry_delay} seconds...")
          sleep retry_delay
          retry_delay = [retry_delay * 2, 60].min  # a little backoff helps when launching thousands
        end
        logger.info("Never got the required vote count of #{required_votes}/#{unanimity} after #{timeout} seconds; public IP did not converge.")
        return nil
      end
    end
  end
end
