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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'platform'))

module RightScale

  class CloudUtilities

    # Does an interface have the given mac address?
    #
    # === Parameters
    # ohai(Mash):: ohai state
    # mac(String):: MAC address to find
    #
    # === Return
    # (Boolean):: true if there is an interface with the giiven mac address
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

    # Recursively retrieves and flattens the hierarchy of metadata.  The key names represent the path to the data.
    #
    # === Parameters
    # url(String):: url to the metadata service
    # parent_key(String)::Optional - used for recursion. appended to the url when querying.
    # keys(String)::Optional - list of metadata to retrieve.  if not provided
    #                          assumes the metadata service will provide the set of keys.
    #
    # === Return
    # cloud_settings(Mash):: collection of data found
    def self.metadata(url, parent_key='', keys=nil)
      cloud_settings = Mash.new

      keys ||= query_uri("#{url}/").split("\n")
      keys.each do |metadata_key_name|
        key = "#{parent_key}#{metadata_key_name.gsub(/\=.*$/, '/')}"
        if key[-1..-1] != '/'
          data = query_uri("#{url}/#{URI.escape(key)}").split("\n")
          cloud_settings[key.gsub(/\-|\//, '_').to_sym] = (data.size == 1) ? data.first : data
        else
          cloud_settings.update(metadata(url, key, query_uri("#{url}/#{URI.escape(key)}").split("\n")))
        end
      end

      cloud_settings
    end

    # Retrieves the data from the given url
    #
    # === Parameters
    # url(String):: url to the userdata service
    #
    # === Return
    # userdata(String|nil):: userdata or nil if cannot access the url
    def self.userdata(url)
      userdata = nil

      # assumes the only expected error is the 404 if there's no user-data
      begin
        userdata = query_uri("#{url}/")
      rescue OpenURI::HTTPError
      end

      userdata
    end

    # Finds the first ip address for a given interface in the ohai mash
    #
    # === Parameters
    # ohai(Mash):: ohai state
    # interface(Symbol):: symbol of the interface (:eth0, :eth1, ...)
    #
    # === Return
    # address(String|nil):: ip address associated with the given interface, nil if interface could not be found
    def self.ip_for_interface(ohai, interface)
      address = nil
      if ohai[:network] != nil &&
         ohai[:network][:interfaces] != nil &&
         ohai[:network][:interfaces][interface] != nil &&
         ohai[:network][:interfaces][interface][:addresses] != nil

        addresses = ohai[:network][:interfaces][interface][:addresses].find { |key, item| item['family'] == 'inet' }
        address = addresses.first unless addresses.nil?
      end

      address
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

    # The cloud this instance is in
    #
    # === Return
    # @@cloud(Symbol):: symbolized name of the cloud (:ec2, :rackspace, :cloudstack, :eucalyptus, ...)
    def self.cloud
      #unless defined?(@@cloud)
      @@cloud = :unknown

      cloud_file = File.normalize_path(File.join(RightScale::Platform.filesystem.right_scale_state_dir, 'cloud'))
      if File.exist?(cloud_file)
        @@cloud = File.read(cloud_file).strip.downcase.to_sym
        # Note: hack for cloudstack name until all references to vmops are converted to cloudstack
        @@cloud = :cloudstack if @@cloud == :vmops
      end
      #end

      @@cloud
    end

    # Is this instance in a given cloud?
    #
    # === Parameters
    # expected_cloud(Symbol):: desired cloud (:ec2, :rackspace, :cloudstack, :eucalyptus, ...)
    #
    # === Block
    # Heuristic to be used if the cloud cannot be discovered by CloudUtilities#cloud.  Given block
    # must evaluate to true if on the cloud and false otherwise.
    #
    # === Return
    # (Boolean):: true if on cloud, or cloud cannot be determined, false otherwise.
    def self.is_cloud?(expected_cloud, & block)
      block ||= lambda { true }
      case cloud
        when expected_cloud then
          return true
        when :unknown then
          return block.call(expected_cloud)
        else
          return false
      end
    end

    protected
    # performs an HTTP GET with retry logic.
    #
    # === Parameters
    # uri(String):: URI to query.
    #
    # === Returns
    # out(String):: body of GET response
    #
    # === Raises
    # OpenURI::HTTPError on failure to get valid response
    # IOError on timeout
    def self.query_uri(uri)
      retry_max_time = 30 * 60
      retry_delay = 1
      retry_max_delay = 64
      start_time = Time.now
      end_time = start_time + retry_max_time
      while true
        begin
          Ohai::Log.debug("Querying \"#{uri}\"...")
          return OpenURI.open_uri(uri).read
        rescue OpenURI::HTTPError => e
          # 404 Not Found is not retryable (server resonded but metadata path was
          # invalid).
          if e.message[0, 4] == "404 "
            raise
          end
          Ohai::Log.warn("#{e.class}: #{e.message}")
        rescue Net::HTTPBadResponse => e
          # EC2 metadata server returns bad responses periodically.
          Ohai::Log.warn("#{e.class}: #{e.message}")
        rescue Net::HTTPHeaderSyntaxError => e
          # just to be as robust as possible.
          Ohai::Log.warn("#{e.class}: #{e.message}")
        end
        now_time = Time.now
        if now_time < end_time
          sleep_delay = [end_time - now_time + 0.1, retry_delay].min
          retry_delay = [retry_max_delay, retry_delay * 2].min
          sleep sleep_delay
        else
          raise IOError, "Could not contact metadata server; retry limit exceeded."
        end
      end
    end
  end
end
