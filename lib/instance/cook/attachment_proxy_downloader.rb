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

class String
  unless method_defined?(:starts_with?)
    def starts_with?(prefix)
      prefix = prefix.to_s
      self[0, prefix.length] == prefix
    end
  end
end

module RightScale

  class AttachmentProxyDownloader < AttachmentDownloader

    # Environment variables to examine for proxy settings, in order.
    PROXY_ENVIRONMENT_VARIABLES = ['HTTPS_PROXY', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY']

    # Initializes an AttachmentProxyDownloader with a list of hostnames
    #
    # The purpose of this method is to instantiate an AttachmentProxyDownloader
    #
    # === Parameters
    # @param <[String]> Hostnames to resolve
    #
    # === Return
    # @return [AttachmentProxyDownloader]

    def initialize(hostnames)
      super
      proxy_var = PROXY_ENVIRONMENT_VARIABLES.detect { |v| ENV.has_key?(v) }
      @proxy = ENV[proxy_var].match(/^[[:alpha:]]+:\/\//) ? URI.parse(ENV[proxy_var]) : URI.parse("http://" + ENV[proxy_var])
    end

    protected

    # Streams data from a Repose server
    #
    # The purpose of this method is to stream the specified specified resource from Repose
    # If a failure is encountered it will provide proper feedback regarding the nature
    # of the failure
    #
    # === Parameters
    # @param [String] Resource URI to parse and fetch
    #
    # === Block
    # @yield [] A block is mandatory
    # @yieldreturn [String] The stream that is being fetched

    def stream(resource)
      client = get_http_client
      resource = URI::parse(resource)
      raise ArgumentError, "Invalid resource provided.  Resource must be a fully qualified URL" unless resource

      begin
        balancer.request do |endpoint|
          RightSupport::Net::SSL.with_expected_hostname(ips[endpoint]) do
            logger.info("Requesting '#{sanitized_resource}' from '#{endpoint}'")
            logger.debug("Requesting '#{resource.scheme}://#{endpoint}#{resource.path}?#{resource.query}' from '#{endpoint}'")
            client.get("#{resource.scheme}://#{endpoint}#{resource.path}?#{resource.query}", {:verify_ssl => OpenSSL::SSL::VERIFY_PEER, :ssl_ca_file => get_ca_file}) do |response, request, result|
              @size = result.content_length
              yield response
            end
          end
        end
      rescue Exception => e
        message = parse(e)
        logger.error("Request '#{sanitized_resource}' failed - #{message}")
        raise ConnectionException, message if message.include?('Errno::ECONNREFUSED') || message.include?('SocketError')
        raise DownloadException, message
      end
    end

    # Instantiates an HTTP Client
    #
    # The purpose of this method is to create an HTTP Client that will be used to
    # make requests in the download method
    #
    # === Return
    # @return [RightSupport::Net::HTTPClient]

    def get_http_client
      RestClient.proxy = @proxy.to_s
      RestClient
    end

  end

end