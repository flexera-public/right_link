#
# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'metadata_provider'))
require File.expand_path(File.join(File.dirname(__FILE__), 'cloud_info'))
require 'tmpdir'
require 'right_http_connection'
require 'uri'

module RightScale

  # Implements MetadataProvider for EC2.
  class Ec2MetadataProvider < MetadataProvider

    class HttpMetadataException < Exception; end

    # === Parameters
    # options[:logger](Logger):: logger (required)
    def initialize(options)
      raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]
    end

    # Fetches EC2 metadata for the current instance.
    #
    # === Returns
    # metadata(Hash):: tree of metadata
    def metadata
      raise "Unexpected leftover connections" if @connections
      @connections = {}
      url = RightScale::CloudInfo.metadata_server_url + '/latest/meta-data/'
      return recursive_fetch_metadata(url)
    ensure
      @connections.each_value do |connection|
        connection.finish
      end
      @connections = {}
    end

    private

    # max wait 64 (2**6) sec between retries
    RETRY_BACKOFF_MAX = 6

    # retry 10 times maximum
    RETRY_MAX_ATTEMPTS = 10

    # retry factor (which can be monkey-patched for quicker testing of retries)
    RETRY_DELAY_FACTOR = 1

    # Recursively grabs a tree of metadata and uses it to populate a tree of
    # metadata.
    #
    # === Parameters
    # url(String):: URL to query for metadata.
    #
    # === Returns
    # tree_metadata(Hash):: tree of metadata
    def recursive_fetch_metadata(url)

      # query URL expecting a plain text list of URL subpaths delimited by
      # newlines.
      tree_metadata = {}
      sub_paths = get_from(url)
      sub_paths.each do |sub_path|
        sub_path = sub_path.strip
        unless sub_path.empty?

          # an equals means there is a subtree to query by the key preceeding
          # the equals sign.
          # example: /public_keys/0=pubkey_name
          equals_index = sub_path.index('=')
          if equals_index
            sub_path = sub_path[0,equals_index]
            sub_path += "/"
          end

          # a URL ending with forward slash is a branch, otherwise a leaf
          if sub_path =~ /\/$/
            tree_metadata[sub_path.chomp('/')] = recursive_fetch_metadata(url + sub_path)
          else
            tree_metadata[sub_path] = get_from(url + sub_path)
          end

        end
      end

      return tree_metadata
    end

    # Requests metadata (in any form) from the given URL.
    #
    # === Parameters
    # url(String):: URL to query for metadata.
    #
    # === Return
    # result(String):: body of response
    #
    # === Raise
    # HttpMetadataException:: on failure to retrieve metadata
    def get_from(url)
      attempts = 0
      while true
        # get.
        result = http_get(url)
        return result if result

        # retry, if allowed.
        attempts += 1
        if snooze(attempts)
          @logger.info("Retrying \"#{url}\"...")
        else
          raise HttpMetadataException, "Could not contact metadata server; retry limit exceeded."
        end
      end
    end

    # Exponential backoff sleep algorithm.  Returns true if processing
    # should continue or false if the maximum number of attempts has
    # been exceeded.
    #
    # === Parameters
    # attempts(int):: number of attempts
    #
    # === Return
    # result(Boolean):: true to continue, false to give up
    def snooze(attempts)
      if attempts > RETRY_MAX_ATTEMPTS
        @logger.debug("Exceeded retry limit of #{RETRY_MAX_ATTEMPTS}.")
        false
      else
        sleep_exponent = [attempts, RETRY_BACKOFF_MAX].min
        sleep RETRY_DELAY_FACTOR * (2 ** sleep_exponent)
        true
      end
    end

    # Performs an HTTP get request with built-in retries and redirection based
    # on HTTP responses.
    #
    # === Parameters
    # attempts(int):: number of attempts
    #
    # === Return
    # result(String):: body of response or nil
    def http_get(url, keep_alive = true)
      uri = safe_parse_http_uri(url)
      history = []
      loop do
        @logger.debug("#{uri}")

        # keep history of live connections for more efficient redirection.
        host = uri.host
        connection = @connections[host] ||= Rightscale::HttpConnection.new(:logger => @logger)

        # prepare request. ensure path not empty due to Net::HTTP limitation.
        #
        # note that the default for Net::HTTP is to close the connection after
        # each request (contrary to expected conventions). we must be explicit
        # about keep-alive if we want that behavior.
        request = Net::HTTP::Get.new(uri.path)
        request['Connection'] = keep_alive ? 'keep-alive' : 'close'

        # get.
        response = connection.request(:protocol => uri.scheme, :server => uri.host, :port => uri.port, :request => request)
        return response.body if response.kind_of?(Net::HTTPSuccess)
        if response.kind_of?(Net::HTTPServerError) || response.kind_of?(Net::HTTPNotFound)
          @logger.debug("Request failed but can retry; #{response.class.name}")
          return nil
        elsif response.kind_of?(Net::HTTPRedirection)
          # keep history of redirects.
          history << uri.to_s
          location = response['Location']
          uri = safe_parse_http_uri(location)
          if location.absolute?
            if history.include?(uri.to_s)
              @logger.error("Circular redirection to #{location.inspect} detected; giving up")
              return nil
            else
              # redirect and continue in loop.
              @logger.debug("Request redirected to #{location.inspect}: #{response.class.name}")
            end
          else
            # can't redirect without an absolute location.
            @logger.error("Unable to redirect to metadata server location #{location.inspect}: #{response.class.name}")
            return nil
          end
        else
          # not retryable.
          #
          # note that the EC2 metadata server is known to give malformed
          # responses on rare occasions, but the right_http_connection will
          # consider these to be 'bananas' and retry automatically (up to a
          # pre-defined limit).
          @logger.error("Request for metadata failed: #{response.class.name}")
          raise HttpMetadataException, "Request for metadata failed: #{response.class.name}"
        end
      end
    end

    # Handles some cases which raise exceptions in the URI class.
    #
    # === Parameters
    # url(String)
    def safe_parse_http_uri(url)
      begin
        uri = URI.parse(url)
      rescue URI::InvalidURIError => e
        # URI raises an exception for URLs like "<IP>:<port>"
        # (e.g. "127.0.0.1:123") unless they also have scheme (e.g. http)
        # prefix. we can do better than that.
        raise e if url.start_with?("http://") || url.start_with?("https://")
        uri = URI.parse("http://" + url)
        uri = URI.parse("https://" + url) if uri.port == 443
        url = uri.to_s
      end

      # supply any missing default values to make URI as complete as possible.
      if uri.scheme.nil?
        scheme = (uri.port == 443) ? 'https' : 'http'
        uri = URI.parse("#{scheme}://#{url}")
        url = uri.to_s
      end
      if uri.path.to_s.empty?
        uri = URI.parse("#{url}/")
        url = uri.to_s
      end
      return uri
    end

  end

end
