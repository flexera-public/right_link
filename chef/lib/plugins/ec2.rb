#
# Author:: Tim Dysinger (<tim@dysinger.net>)
# Author:: Benjamin Black (<bb@opscode.com>)
# Author:: Christopher Brown (<cb@opscode.com>)
# Copyright:: Copyright (c) 2009 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

provides "ec2"

require 'open-uri'
require 'socket'

require_plugin "hostname"
require_plugin "kernel"
require_plugin "network"

EC2_METADATA_ADDR = "169.254.169.254" unless defined?(EC2_METADATA_ADDR)
EC2_METADATA_URL = "http://#{EC2_METADATA_ADDR}/2008-02-01/meta-data" unless defined?(EC2_METADATA_URL)
EC2_USERDATA_URL = "http://#{EC2_METADATA_ADDR}/2008-02-01/user-data" unless defined?(EC2_USERDATA_URL)

def can_metadata_connect?(addr, port, timeout=10)
  t = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
  saddr = Socket.pack_sockaddr_in(port, addr)
  connected = false

  # need retry logic because hvm server can reject under heavy load.
  start_time = Time.now
  end_time = start_time + timeout
  while (false == connected && Time.now < end_time)
    begin
      t.connect_nonblock(saddr)
    rescue Errno::EINPROGRESS => e
      r,w,e = IO::select(nil,[t],nil,timeout)
      if !w.nil?
        connected = true
        t.close
      end
    rescue SystemCallError => e
    end
  end

  connected
end

def has_ec2_mac?
  network[:interfaces].values.each do |iface|
    unless iface[:arp].nil?
      return true if iface[:arp].value?("fe:ff:ff:ff:ff:ff")
    end
  end
  false
end

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
def query_uri(uri)
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
      if e.message[0,4] == "404 "
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

def metadata(id='')
  query_uri("#{EC2_METADATA_URL}/#{id}").split("\n").each do |o|
    key = "#{id}#{o.gsub(/\=.*$/, '/')}"
    if key[-1..-1] != '/'
      ec2[key.gsub(/\-|\//, '_').to_sym] =
        query_uri("#{EC2_METADATA_URL}/#{key}")
    else
      metadata(key)
    end
  end
end

def userdata()
  ec2[:userdata] = nil
  # assumes the only expected error is the 404 if there's no user-data
  begin
    ec2[:userdata] = query_uri("#{EC2_USERDATA_URL}/")
  rescue OpenURI::HTTPError
  end
end

def looks_like_ec2?
  # Try non-blocking connect so we don't "block" if
  # the Xen environment is *not* EC2
  has_ec2_mac? && can_metadata_connect?(EC2_METADATA_ADDR,80)
end

if looks_like_ec2?
  ec2 Mash.new
  self.metadata
  self.userdata
end
