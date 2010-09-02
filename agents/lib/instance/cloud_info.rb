#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Discover the IP

require 'fileutils'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'platform'))

SHEBANG_REGEX = /^#!/

module RightScale
  class CloudInfo
    def self.metadata_server_url
      begin
        #Resolve Euca metadata server hostname
        addrs = Socket.gethostbyname('euca-metadata')[3..-1]
        #Select only IPv4 addresses
        addrs = addrs.select { |x| x.length == 4 }
        #Choose a random IPv4 address
        raw_ip = addrs[rand(addrs.size)]
        #Transform binary IP address into string representation
        ip = []
        raw_ip.each_byte { |x| ip << x.to_s }
        host = ip.join('.')
        port = 8773
      rescue Exception => e
        #Fall back to EC2-style fixed IP address
        host = '169.254.169.254'
        port = 80
      end

      return "http://#{host}:#{port}"
    end
  end
end