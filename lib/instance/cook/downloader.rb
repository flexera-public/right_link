#
# Copyright (c) 2009-2012 RightScale Inc
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

module RightScale

  # Abstract download capabilities
  class Downloader

    class ConnectionException < Exception; end
    class DownloadException < Exception; end

    include RightSupport::Log::Mixin

    # (Integer) Size in bytes of last successful download (nil if none)
    attr_reader :size

    # (Integer) Speed in bytes/seconds of last successful download (nil if none)
    attr_reader :speed

    # (String) Last resource downloaded
    attr_reader :sanitized_resource

    def download(resource, options = {})
      @size = 0
      @speed = 0
      @sanitized_resource = sanitize_resource(resource)
      t0 = Time.now
      file = _download(resource, options)
      @speed = size / (Time.now - t0)
      return file
    end

    def _download(resource, options = {})

    end

    # Resolve a list of hostnames to a hash of Hostname => IP Addresses
    #
    # The purpose of this method is to lookup all IP addresses per hostname and
    # build a lookup hash that maps IP addresses back to their original hostname
    # so we can perform TLS hostname verification.
    #
    # === Parameters
    # @param <[String]> Hostnames to resolve
    #
    # === Return
    # @return [Hash]
    #   * :key [<String>] a key (IP Address) that accepts a hostname string as it's value

    def resolve(hostnames)
      ips = {}
      hostnames.each do |hostname|
        infos = nil
        begin
          infos = Socket.getaddrinfo(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
        rescue Exception => e
          logger.error "Failed to resolve hostnames: #{e.class.name}: #{e.message}"
          raise e
        end

        # Randomly permute the addrinfos of each hostname to help spread load.
        infos.shuffle.each do |info|
          ip = info[3]
          ips[ip] = hostname
        end
      end
      ips
    end

    # Message summarizing last successful download details
    #
    # === Return
    # @return [String] Message with last downloaded resource, download size and speed

    def details
      "Downloaded #{@sanitized_resource} (#{ scale(size.to_i).join(' ') }) at #{ scale(speed.to_i).join(' ') }/s"
    end

    # Return a sanitized value from given argument
    #
    # The purpose of this method is to return a value that can be securely
    # displayed in logs and audits
    #
    # === Parameters
    # @param [String] 'Resource' to parse
    #
    # === Return
    # @return [String] 'Resource' portion of resource provided

    def sanitize_resource(resource)
      resource.split('?').first
    end

    # Return scale and scaled value from given argument
    #
    # The purpose of this method is to convert bytes to a nicer format for display
    # Scale can be B, KB, MB or GB
    #
    # === Parameters
    # @param [Integer] Value in bytes
    #
    # === Return
    # @return <[Integer], [String]> First element is scaled value, second element is scale

    def scale(value)
      case value
        when 0..1023
          [value, 'B']
        when 1024..1024**2 - 1
          [value / 1024, 'KB']
        when 1024^2..1024**3 - 1
          [value / 1024**2, 'MB']
        else
          [value / 1024**3, 'GB']
      end
    end

  end

end