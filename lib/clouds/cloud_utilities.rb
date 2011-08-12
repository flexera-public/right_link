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

  end
end
