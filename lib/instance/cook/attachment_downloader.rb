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

    # Downloads an attachment from Repose
    #
    # The purpose of this method is to download the specified attachment from Repose
    # If a failure is encountered it will provide proper feedback regarding the nature
    # of the failure
    #
    # === Parameters
    # @param [String] Resource URI to parse and fetch
    # @param [String] Destination for fetched resource
    #
    # === Return
    # @return [File] The file that was downloaded

    def _download(resource, dest)
      begin
        attachment_dir = File.dirname(dest)
        FileUtils.mkdir_p(attachment_dir)
        tempfile = Tempfile.open('attachment', attachment_dir)
        tempfile.binmode
        stream(resource) do |response|
          tempfile << response
        end
        File.unlink(dest) if File.exists?(dest)
        File.link(tempfile.path, dest)
        tempfile.close!
      rescue Exception => e
        tempfile.close! unless tempfile.nil?
        raise e
      end
      tempfile
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
            client.request(:get, "#{resource.scheme}://#{endpoint}#{resource.path}?#{resource.query}", {:verify_ssl => OpenSSL::SSL::VERIFY_PEER, :ssl_ca_file => get_ca_file}) do |response, request, result|
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