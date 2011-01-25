#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'right_http_connection'

#TODO TS factor this into its own source file; make it slightly less monkey-patchy (e.g. mixin)
module OpenSSL
  module SSL
    class SSLSocket
      alias post_connection_check_without_hack post_connection_check

      # Class variable. Danger! THOU SHALT NOT CAUSE 'openssl/ssl' TO RELOAD
      # nor shalt thou use this monkey patch in conjunction with Rails
      # auto-loading or class-reloading mechanisms! You have been warned...
      @@hostname_override = nil

      def self.hostname_override=(hostname_override)
        @@hostname_override = hostname_override
      end

      def post_connection_check(hostname)
        return post_connection_check_without_hack(@@hostname_override || hostname)
      end
    end
  end
end

module RightScale
  class ReposeDownloader
    #max wait 64 (2**6) sec between retries
    REPOSE_RETRY_BACKOFF_MAX = 6
    REPOSE_RETRY_MAX_ATTEMPTS = 10

    class ReposeConnectionFailure < Exception
    end

    class ReposeServerFailure < Exception
    end

    # Prepare to request a resource from the Repose mirror.
    #
    # === Parameters
    # scope(String):: the scope of the resource to request
    # resource(String):: the name of the resource
    # ticket(String):: the authorization token for the resource
    # name(String):: human readable name (for error messages and the like)
    # exception(Exception):: the exception to throw if we are unable to download the resource
    def initialize(scope, resource, ticket, name, exception)
      @scope = scope
      @resource = resource
      @ticket = ticket
      @name = name
      @exception = exception
      @failures  = 0
    end

    # Request the resource from the Repose mirror, performing retry as
    # necessary. Block until the resource has been downloaded, or
    # until permanent failure has been determined.
    #
    # === Parameters
    # scope(String):: the scope of the resource to request
    # resource(String):: the name of the resource
    # ticket(String):: the authorization token for the resource
    # exception(Exception):: the exception to throw if we are unable to download the resource
    #
    # === Block
    # If the request succeeds this method will yield, passing
    # the HTTP response object as its sole argument.
    #
    # === Raise
    # exception:: if a permanent failure happened
    # ReposeServerFailure:: if no Repose server could be contacted
    #
    # === Return
    # true:: always returns true
    def request
      @repose_connection ||= next_repose_server
      cookie = Object.new
      result = cookie
      attempts = 0

      while result == cookie
        RightLinkLog.info("Requesting /#{@scope}/#{@resource}")
        request = Net::HTTP::Get.new("/#{@scope}/#{@resource}")
        request['Cookie'] = "repose_ticket=#{@ticket}"
        request['Host'] = @repose_connection.first

        @repose_connection.last.request(
            :protocol => 'https', :server => @repose_connection.first, :port => '443',
            :request => request) do |response|
          if response.kind_of?(Net::HTTPSuccess)
            @failures = 0
            yield response
            result = true
          elsif response.kind_of?(Net::HTTPServerError) || response.kind_of?(Net::HTTPNotFound)
            RightLinkLog.warn("Request failed - #{response.class.name} - retry")
            if snooze(attempts)
              @repose_connection = next_repose_server
            else
              RightLinkLog.error("Request failed - too many attempts, giving up")
              result = @exception.new(@scope, @resource, @name, "too many attempts")
              next
            end
          else
            RightLinkLog.error("Request failed - #{response.class.name} - give up")
            result = @exception.new(@scope, @resource, @name, response)
          end
        end
        attempts += 1
      end

      raise result if result.kind_of?(Exception)
      return true
    end

    # Find the next Repose server in the list. Perform special TLS certificate voodoo to comply
    # safely with global URL scheme.
    #
    # === Raise
    # ReposeServerFailure:: if a permanent failure happened
    #
    # === Return
    # server(Array):: [ ip address of server, HttpConnection to server ]
    def next_repose_server
      attempts = 0
      loop do
        ip         = @@ips[ @@index % @@ips.size ]
        hostname   = @@hostnames[ip]
        @@index += 1
        #TODO monkey-patch OpenSSL hostname verification
        RightLinkLog.info("Connecting to cookbook server #{ip} (#{hostname})")
        begin
          OpenSSL::SSL::SSLSocket.hostname_override = hostname

          #The CA bundle is a basically static collection of trusted certs of top-level
          #CAs. It should be provided by the OS, but because of our cross-platform nature
          #and the lib we're using, we need to supply our own. We stole curl's.
          ca_file = File.normalize_path(File.join(File.dirname(__FILE__), 'ca-bundle.crt'))

          connection = Rightscale::HttpConnection.new(:user_agent => "RightLink v#{RightLinkConfig.protocol_version}",
                                                      :logger => @logger,
                                                      :exception => ReposeConnectionFailure,
                                                      :ca_file => ca_file)
          health_check = Net::HTTP::Get.new('/')
          health_check['Host'] = hostname
          result = connection.request(:server => ip, :port => '443', :protocol => 'https',
                                      :request => health_check)
          if result.kind_of?(Net::HTTPSuccess)
            @failures = 0
            return [ip, connection]
          else
            RightLinkLog.error "Health check unsuccessful: #{result.class.name}"
            unless snooze(attempts)
              RightLinkLog.error("Can't find any repose servers, giving up")
              raise ReposeServerFailure.new("too many attempts")
            end
          end
        rescue ReposeConnectionFailure => e
          RightLinkLog.error "Connection failed: #{e.message}"
          unless snooze(attempts)
            RightLinkLog.error("Can't find any repose servers, giving up")
            raise ReposeServerFailure.new("too many attempts")
          end
        end
        attempts += 1
      end
    end

    # Exponential backoff sleep algorithm.  Returns true if processing
    # should continue or false if the maximum number of attempts has
    # been exceeded.
    #
    # === Parameters
    # attempts(Fixnum):: number of attempts
    #
    # === Return
    # Boolean:: whether to continue
    def snooze(attempts)
      if attempts > REPOSE_RETRY_MAX_ATTEMPTS
        false
      else
        @failures = [@failures + 1, REPOSE_RETRY_BACKOFF_MAX].min
        sleep (2**@failures)
        true
      end
    end

    # Given a sequence of preferred hostnames, lookup all IP addresses and store
    # an ordered sequence of IP addresses from which to attempt cookbook download.
    # Also build a lookup hash that maps IP addresses back to their original hostname
    # so we can perform TLS hostname verification.
    #
    # === Parameters
    # hostnames(Array):: hostnames
    #
    # === Return
    # true:: always returns true
    def self.discover_repose_servers(hostnames)
      @@index     = 0
      @@ips       = []
      @@hostnames = {}
      hostnames = [hostnames] unless hostnames.respond_to?(:each)
      hostnames.each do |hostname|
        infos = Socket.getaddrinfo(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)

        #Randomly permute the addrinfos of each hostname to help spread load.
        infos.shuffle.each do |info|
          ip = info[3]
          @@ips << ip
          @@hostnames[ip] = hostname
        end
      end

      true
    end
  end
end
