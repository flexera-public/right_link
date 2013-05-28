#
# Copyright (c) 2009-2013 RightScale Inc
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

require 'right_support/net/http_client'
require 'uri'

module RightScale

  # Abstract download capabilities
  class ReposeDownloader

    # Environment variables to examine for proxy settings, in order.
    PROXY_ENVIRONMENT_VARIABLES = ['HTTPS_PROXY', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY']

    # Class names of exceptions to be re-raised as a ConnectionException
    CONNECTION_EXCEPTIONS = ['Errno::ECONNREFUSED', 'Errno::ETIMEDOUT', 'SocketError',
                             'RestClient::InternalServerError', 'RestClient::RequestTimeout']

    # max timeout 8 (2**3) minutes for each retry
    RETRY_BACKOFF_MAX = 3

    # retry 5 times maximum
    RETRY_MAX_ATTEMPTS = 5

    class ConnectionException < Exception; end
    class DownloadException < Exception; end

    include RightSupport::Log::Mixin

    # (Integer) Size in bytes of last successful download (nil if none)
    attr_reader :size

    # (Integer) Speed in bytes/seconds of last successful download (nil if none)
    attr_reader :speed

    # (String) Last resource downloaded
    attr_reader :sanitized_resource

    # Hash of IP Address => Hostname
    attr_reader :ips

    # Initializes a Downloader with a list of hostnames
    #
    # The purpose of this method is to instantiate a Downloader.
    # It will perform DNS resolution on the hostnames provided
    # and will configure a proxy if necessary
    #
    # === Parameters
    # @param <[String]> Hostnames to resolve
    #
    # === Return
    # @return [Downloader]
    #
    def initialize(hostnames)
      raise ArgumentError, "At least one hostname must be provided" if hostnames.empty?
      hostnames = [hostnames] unless hostnames.respond_to?(:each)
      @ips = resolve(hostnames)
      @hostnames = hostnames

      proxy_var = PROXY_ENVIRONMENT_VARIABLES.detect { |v| ENV.has_key?(v) }
      @proxy = ENV[proxy_var].match(/^[[:alpha:]]+:\/\//) ? URI.parse(ENV[proxy_var]) : URI.parse("http://" + ENV[proxy_var]) if proxy_var
    end

    # Downloads an attachment from Repose
    #
    # The purpose of this method is to download the specified attachment from Repose
    # If a failure is encountered it will provide proper feedback regarding the nature
    # of the failure
    #
    # === Parameters
    # @param [String] Resource URI to parse and fetch
    #
    # === Block
    # @yield [] A block is mandatory
    # @yieldreturn [String] The stream that is being fetched
    #
    def download(resource)
      client              = get_http_client
      @size               = 0
      @speed              = 0
      @sanitized_resource = sanitize_resource(resource)
      resource            = parse_resource(resource)
      attempts            = 0

      begin
        balancer.request do |endpoint|
          RightSupport::Net::SSL.with_expected_hostname(ips[endpoint]) do
            logger.info("Requesting '#{sanitized_resource}' from '#{endpoint}'")

            attempts += 1
            t0 = Time.now

            # Previously we accessed RestClient directly and used it's wrapper method to instantiate 
            # a RestClient::Request object.  This wrapper was not passing all options down the stack
            # so now we invoke the RestClient::Request object directly, passing it our desired options
            client.execute(:method => :get, :url => "https://#{endpoint}:443#{resource}", :timeout => calculate_timeout(attempts), :verify_ssl => OpenSSL::SSL::VERIFY_PEER, :ssl_ca_file => get_ca_file, :headers => {:user_agent => "RightLink v#{AgentConfig.protocol_version}"}) do |response, request, result|
              if result.kind_of?(Net::HTTPSuccess)
                @size = result.content_length
                @speed = @size / (Time.now - t0)
                yield response
              else
                response.return!(request, result)
              end
            end
          end
        end
      rescue Exception => e
        list = parse_exception_message(e)
        message = list.join(", ")
        logger.error("Request '#{sanitized_resource}' failed - #{message}")
        raise ConnectionException, message unless (list & CONNECTION_EXCEPTIONS).empty?
        raise DownloadException, message
      end
    end

    # Message summarizing last successful download details
    #
    # === Return
    # @return [String] Message with last downloaded resource, download size and speed
    #
    def details
      "Downloaded '#{@sanitized_resource}' (#{ scale(size.to_i).join(' ') }) at #{ scale(speed.to_i).join(' ') }/s"
    end

    protected

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
    #
    def resolve(hostnames)
      ips = {}
      hostnames.each do |hostname|
        infos = nil
        attempts = RETRY_MAX_ATTEMPTS
        begin
          infos = Socket.getaddrinfo(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)
        rescue Exception => e
          if attempts > 0
            attempts -= 1
            retry
          else
            logger.error "Failed to resolve hostnames: #{e.class.name}: #{e.message}"
            raise e
          end
        end

        # Randomly permute the addrinfos of each hostname to help spread load.
        infos.shuffle.each do |info|
          ip = info[3]
          ips[ip] = hostname
        end
      end
      ips
    end

    # Parses a resource into a Repose-appropriate format
    #
    # The purpose of this method is to parse the resource given into the proper resource
    # format that the ReposeDownloader class is expecting
    #
    # === Parameters
    # @param [String] Resource URI to parse
    #
    # === Block
    # @return [String] The parsed URI
    #
    def parse_resource(resource)
      resource = URI::parse(resource)
      raise ArgumentError, "Invalid resource provided.  Resource must be a fully qualified URL" unless resource
      "#{resource.path}?#{resource.query}"
    end

    # Parse Exception message and return it
    #
    # The purpose of this method is to parse the message portion of RequestBalancer
    # Exceptions to determine the actual Exceptions that resulted in all endpoints
    # failing to return a non-Exception.
    #
    # === Parameters
    # @param [Exception] Exception to parse
    #
    # === Return
    # @return [Array] List of exception class names

    def parse_exception_message(e)
      if e.kind_of?(RightSupport::Net::NoResult)
        # Expected format of exception message: "... endpoints: ('<ip address>' => <exception class name array>, ...)""
        i = 0
        e.message.split(/\[|\]/).select {((i += 1) % 2) == 0 }.map { |s| s.split(/,\s*/) }.flatten
      else
        [e.class.name]
      end
    end

    # Orders ips by hostnames
    #
    # The purpose of this method is to sort ips of hostnames so it tries all IPs of hostname 1, 
    # then all IPs of hostname 2, etc
    #
    # == Return
    # @return [Array] array of ips ordered by hostnames
    #
    def hostnames_ips
      @hostnames.map do |hostname|
        ips.reject { |ip, host| host != hostname }.keys
      end.flatten
    end

    # Create and return a RequestBalancer instance
    #
    # The purpose of this method is to create a RequestBalancer that will be used
    # to service all 'download' requests.  Once a valid endpoint is found, the
    # balancer will 'stick' with it. It will consider a response of '408: RequestTimeout' and
    # '500: InternalServerError' as retryable exceptions and all other HTTP error codes to
    # indicate a fatal exception that should abort the load-balanced request
    #
    # === Return
    # @return [RightSupport::Net::RequestBalancer]
    #
    def balancer
      @balancer ||= RightSupport::Net::RequestBalancer.new(
        hostnames_ips,
        :policy => RightSupport::Net::LB::Sticky,
        :retry  => RETRY_MAX_ATTEMPTS,
        :fatal  => lambda do |e|
          if RightSupport::Net::RequestBalancer::DEFAULT_FATAL_EXCEPTIONS.any? { |c| e.is_a?(c) }
            true
          elsif e.respond_to?(:http_code) && (e.http_code != nil)
            (e.http_code >= 400 && e.http_code < 500) && (e.http_code != 408 && e.http_code != 500 )
          else
            false
          end
        end
      )
    end

    # Exponential incremental timeout algorithm.  Returns the amount of 
    # of time to wait for the next iteration
    #
    # === Parameters
    # @param [String] Number of attempts
    #
    # === Return
    # @return [Integer] Timeout to use for next iteration
    #
    def calculate_timeout(attempts)
      timeout_exponent = [attempts, RETRY_BACKOFF_MAX].min
      (2 ** timeout_exponent) * 60
    end

    # Returns a path to a CA file
    #
    # The CA bundle is a basically static collection of trusted certs of top-level CAs.
    # It should be provided by the OS, but because of our cross-platform nature and
    # the lib we're using, we need to supply our own. We stole curl's.
    #
    # === Return
    # @return [String] Path to a CA file
    #
    def get_ca_file
      ca_file = File.normalize_path(File.join(File.dirname(__FILE__), 'ca-bundle.crt'))
    end

    # Instantiates an HTTP Client
    #
    # The purpose of this method is to create an HTTP Client that will be used to
    # make requests in the download method
    #
    # === Return
    # @return [RestClient]
    #
    def get_http_client
      RestClient.proxy = @proxy.to_s if @proxy
      RestClient
      RestClient::Request
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
    #
    def sanitize_resource(resource)
      URI::split(resource)[5].split("/").last
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
    #
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
