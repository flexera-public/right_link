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

require 'uri'

module RightScale

  class AttachmentDownloader < Downloader

    # Hash of IP Address => Hostname
    attr_reader :ips

    # Initializes an AttachmentDownloader with a list of hostnames
    #
    # The purpose of this method is to instantiate an AttachmentDownloader
    #
    # === Parameters
    # @param <[String]> Hostnames to resolve
    #
    # === Return
    # @return [AttachmentDownloader]

    def initialize(hostnames)
      raise ArgumentError, "At least one hostname must be provided" if hostnames.empty?
      hostnames = [hostnames] unless hostnames.respond_to?(:each)
      @ips = resolve(hostnames)
    end

    # Downloads an attachment from Repose
    #
    # The purpose of this method is to download the specified attachment from Repose
    # If a failure is encountered it will provide proper feedback regarding the nature
    # of the failure
    #
    # === Parameters
    # @param <[String]> Hostnames to resolve
    # @option options [Fixnum] :audit_id Audit entry ID to which text should be appended
    # @option options [String] :category Event notification category
    #
    # === Return
    # @return [File]

    def _download(resource, options = {})
      client = get_http_client
      resource = URI::parse(resource)
      raise ArgumentError, "Invalid resource provided.  Resource must be a fully qualified URL" unless resource

      begin
        balancer.request do |endpoint|
          RightSupport::Net::SSL.with_expected_hostname(ips[endpoint]) do
            logger.info("Requesting '#{sanitized_resource}' from '#{endpoint}'")
            logger.debug("Requesting '#{resource.scheme}://#{endpoint}#{resource.path}?#{resource.query}' from '#{endpoint}'")
            client.request(:get, "#{resource.scheme}://#{endpoint}#{resource.path}?#{resource.query}", {:verify_ssl => true, :ssl_ca_file => get_ca_file})
          end
        end
      rescue Exception => e
        message = parse(e)
        logger.error("Request '#{sanitized_resource}' failed - #{message}")
        raise ConnectionException, message if message.include?('Errno::ECONNREFUSED') || message.include?('SocketError')
        raise DownloadException, message
      end
    end

    protected

    # Parse Exception message and return it
    #
    # The purpose of this method is to parse the message portion of RequestBalancer
    # Exceptions to determine the actual Exceptions that resulted in all endpoints
    # failing to return a non-Exception.
    #
    # === Parameters
    # @param [Exception] Exception to parse

    # === Return
    # @return [String] List of Exceptions

    def parse(e)
      if e.kind_of?(RightSupport::Net::NoResult)
        message = e.message.split("Exceptions: ")[1]
      else
        message = e.class.name
      end
      message
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

    def balancer
      @balancer ||= RightSupport::Net::RequestBalancer.new(
          ips.keys,
          :policy => RightSupport::Net::Balancing::StickyPolicy,
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

    # Returns a path to a CA file
    #
    # The CA bundle is a basically static collection of trusted certs of top-level CAs.
    # It should be provided by the OS, but because of our cross-platform nature and
    # the lib we're using, we need to supply our own. We stole curl's.
    #
    # === Return
    # @return [String] Path to a CA file

    def get_ca_file
      ca_file = File.normalize_path(File.join(File.dirname(__FILE__), 'ca-bundle.crt'))
    end

    # Instantiates an HTTP Client
    #
    # The purpose of this method is to create an HTTP Client that will be used to
    # make requests in the download method
    #
    # === Return
    # @return [RightSupport::Net::HTTPClient]

    def get_http_client
      RightSupport::Net::HTTPClient.new({:headers => {:user_agent => "RightLink v#{AgentConfig.protocol_version}"}})
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
      URI::split(resource)[5].split("/")[3]
    end

  end

end