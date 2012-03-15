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
    # re-resolve parameter for RequestBalancer
    REPOSE_RESOLVE_TIME = 15

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
      balancer.request do |host|
        RightSupport::Net::SSL.with_expected_hostname(@@hostnames_hash[host]) do
          connection = make_connection
          Log.info("Requesting /#{host}/#{@scope}/#{@resource.split('?')[0]}")
          request = Net::HTTP::Get.new("/#{@scope}/#{@resource}")
          request['Cookie'] = "repose_ticket=#{@ticket}"
          request['Host'] = host

          connection.request(:protocol => 'https', :server => host,
                                        :port => '443', :request => request) do |response|
            if response.kind_of?(Net::HTTPSuccess)
              yield response
            else
              Log.error("Request failed - #{response.class.name} - give up")
              raise @exception, [@scope, @resource, @name, response]
            end
          end
        end
      end
      return true
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
          hostnames_hash[ip] = hostname
        end
      end
      set_servers(hostnames, hostnames_hash)

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

    # Create a single balancer instance to maximize health check's efficiency
    def balancer
      @balancer ||= RightSupport::Net::RequestBalancer.new(@@hostnames,
                      :policy=>RightSupport::Net::Balancing::StickyPolicy,
                      :resolve => REPOSE_RESOLVE_TIME)
    end

    # Set the servers to use for Repose downloads.
    #
    # === Parameters
    # hostnames(Array):: list of URLs to connect to
    # hostnames_hash(Hash):: IP -> hostname reverse lookup hash
    def self.set_servers(hostnames, hostnames_hash)
      @@hostnames = hostnames
      @@hostnames_hash = hostnames_hash
    end
  end
end
