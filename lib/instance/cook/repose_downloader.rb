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
OpenSSL::SSL::SSLSocket.class_exec {

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

} unless OpenSSL::SSL::SSLSocket.instance_methods.include?('post_connection_check_without_hack')

module RightScale
  # Class centralizing logic for downloading objects from Repose.
  class ReposeDownloader
    # Select appropriate Repose class to use.  Currently, checks the
    # HTTPS_PROXY, HTTP_PROXY, http_proxy and ALL_PROXY environment
    # variables.
    def self.select_repose_class
      proxy_vars = ReposeProxyDownloader::PROXY_ENVIRONMENT_VARIABLES
      if proxy_vars.any? {|var| ENV.has_key?(var)}
        ReposeProxyDownloader
      else
        ReposeDownloader
      end
    end

    # max wait 64 (2**6) sec between retries
    REPOSE_RETRY_BACKOFF_MAX = 6
    # retry 10 times maximum
    REPOSE_RETRY_MAX_ATTEMPTS = 10

    # Exception class representing failure to connect to Repose.
    class ReposeConnectionFailure < Exception
    end

    # Prepare to request a resource from the Repose mirror.
    #
    # === Parameters
    # scope(String):: the scope of the resource to request
    # resource(String):: the name of the resource
    # ticket(String):: the authorization token for the resource
    # name(String):: human readable name (for error messages and the like)
    # exception(Exception):: the exception to throw if we are unable to download the resource.
    #                        Takes one argument which is an array of four elements
    #                        [+scope+, +resource+, +name+, +reason+]
    # logger(Logger):: logger to use
    def initialize(scope, resource, ticket, name, exception, logger)
      @scope = scope
      @resource = resource
      @ticket = ticket
      @name = name
      @exception = exception
      @logger = logger
      @failures  = 0
    end

    # Request the resource from the Repose mirror, performing retry as
    # necessary. Block until the resource has been downloaded, or
    # until permanent failure has been determined.
    #
    # === Block
    # If the request succeeds this method will yield, passing
    # the HTTP response object as its sole argument.
    #
    # === Raise
    # @exception:: if a permanent failure happened
    #
    # === Return
    # true:: always returns true
    def request
      @repose_connection ||= next_repose_server
      cookie = Object.new
      result = cookie
      attempts = 0

      while result == cookie
        Log.info("Requesting /#{@scope}/#{@resource.split('?')[0]}")
        request = Net::HTTP::Get.new("/#{@scope}/#{@resource}")
        request['Cookie'] = "repose_ticket=#{@ticket}"
        request['Host'] = @repose_connection.first

        @repose_connection.last.request(:protocol => 'https', :server => @repose_connection.first,
                                        :port => '443', :request => request) do |response|
          if response.kind_of?(Net::HTTPSuccess)
            @failures = 0
            yield response
            result = true
          elsif response.kind_of?(Net::HTTPServerError) || response.kind_of?(Net::HTTPNotFound)
            Log.warning("Request failed - #{response.class.name} - retry")
            if snooze(attempts)
              @repose_connection = next_repose_server
            else
              Log.error("Request failed - too many attempts, giving up")
              raise @exception, [@scope, @resource, @name, "too many attempts"]
            end
          else
            Log.error("Request failed - #{response.class.name} - give up")
            raise @exception, [@scope, @resource, @name, response]
          end
        end
        attempts += 1
      end

      return true
    end

    # Find the next Repose server in the list. Perform special TLS certificate voodoo to comply
    # safely with global URL scheme.
    #
    # === Raise
    # @exception:: if a permanent failure happened
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
        Log.info("Connecting to cookbook server #{ip} (#{hostname})")
        begin
          OpenSSL::SSL::SSLSocket.hostname_override = hostname

          connection = make_connection
          health_check = Net::HTTP::Get.new('/')
          health_check['Host'] = hostname
          result = connection.request(:server => ip, :port => '443', :protocol => 'https',
                                      :request => health_check)
          if result.kind_of?(Net::HTTPSuccess)
            @failures = 0
            return [ip, connection]
          else
            Log.error("Health check unsuccessful: #{result.class.name}")
            unless snooze(attempts)
              Log.error("Can't find any repose servers, giving up")
              raise @exception, [@scope, @resource, @name, "too many attempts"]
            end
          end
        rescue ReposeConnectionFailure => e
          Log.error("Connection failed", e)
          unless snooze(attempts)
            Log.error("Can't find any repose servers, giving up")
            raise @exception, [@scope, @resource, @name, "too many attempts"]
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
      ips       = []
      hostnames_hash = {}
      hostnames = [hostnames] unless hostnames.respond_to?(:each)
      hostnames.each do |hostname|
        infos = nil
        begin
          infos = Socket.getaddrinfo(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
        rescue Exception => e
          Log.error "Rescued #{e.class.name} resolving Repose hostnames: #{e.message}; retrying"
          retry
        end

        #Randomly permute the addrinfos of each hostname to help spread load.
        infos.shuffle.each do |info|
          ip = info[3]
          ips << ip
          hostnames_hash[ip] = hostname
        end
      end
      set_servers(ips, hostnames_hash)

      true
    end

    protected

    # Return a path to a CA file.  The CA bundle is a basically static
    # collection of trusted certs of top-level CAs. It should be
    # provided by the OS, but because of our cross-platform nature and
    # the lib we're using, we need to supply our own. We stole curl's.
    def get_ca_file
      ca_file = File.normalize_path(File.join(File.dirname(__FILE__), 'ca-bundle.crt'))
    end

    # Make a Rightscale::HttpConnection for later use.
    def make_connection
      Rightscale::HttpConnection.new(:user_agent => "RightLink v#{AgentConfig.protocol_version}",
                                     :logger => @logger,
                                     :exception => ReposeConnectionFailure,
                                     :fail_if_ca_mismatch => true,
                                     :ca_file => get_ca_file)
    end

    # Get the servers that are currently being used for Repose downloads.
    #
    # === Return
    # index(Integer):: Index into ips that is next in the list
    # ips(Array):: list of IP addresses to connect to
    # hostnames(Hash):: IP -> hostname reverse lookup hash
    def self.get_servers
      [@@index, @@ips, @@hostnames]
    end

    # Set the servers to use for Repose downloads.
    #
    # === Parameters
    # ips(Array):: list of IP addresses to connect to
    # hostnames(Hash):: IP -> hostname reverse lookup hash
    def self.set_servers(ips, hostnames)
      @@index = 0
      @@ips = ips
      @@hostnames = hostnames
    end
  end
end
