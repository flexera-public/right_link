#
# Copyright (c) 2011 RightScale Inc
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

require 'right_http_connection'
require 'uri'

module RightScale

  module MetadataSources

    # Provides metadata via a single http connection which is kept alive in the
    # case of a tree of metadata.
    class HttpMetadataSource < MetadataSource

      attr_accessor :host, :port

      def initialize(options)
        raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]
        raise ArgumentError, "options[:hosts] is required" unless @hosts = options[:hosts]
        @host, @port = self.class.select_metadata_server(@hosts)
        @connections = {}
      end

      # Queries for metadata using the given path.
      #
      # === Parameters
      # path(String):: metadata path
      #
      # === Return
      # metadata(String):: query result
      #
      # === Raises
      # QueryFailed:: on any failure to query
      def query(path)
        http_path = "http://#{@host}:#{@port}/#{path}"
        attempts = 0
        while true
          # get.
          result = http_get(http_path)
          return result if result

          # retry, if allowed.
          attempts += 1
          if snooze(attempts)
            @logger.info("Retrying \"#{path}\"...")
          else
            raise QueryFailed, "Could not contact metadata server; retry limit exceeded."
          end
        end
      end

      # Closes any http connections left open after fetching metadata.
      def finish
        @connections.each_value do |connection|
          begin
            connection.finish
          rescue Exception => e
            @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
          end
        end
        @connections = {}
      end

      # selects a host/port by attempting to dig one or more well-known DNS
      # names or IP addresses.
      #
      # === Parameters
      # hosts(Array):: array of hosts in the form [{:host => <dns name or ip address>, :port => <port or nil>}+]
      #
      # === Return
      # result(Array):: pair in form of [<selected host ip address>, <selected port>]
      def self.select_metadata_server(hosts)
        # note that .each works for strings (by newline) and arrays.
        last_exception = nil
        hosts.each do |host_data|
          begin
            # resolve metadata server hostname.
            addrs = Socket.gethostbyname(host_data[:host])[3..-1]

            # select only IPv4 addresses
            addrs = addrs.select { |x| x.length == 4 }

            # choose a random IPv4 address
            raw_ip = addrs[rand(addrs.size)]

            # transform binary IP address into string representation
            ip = []
            raw_ip.each_byte { |x| ip << x.to_s }
            return [ip.join('.'), host_data[:port] || 80]
          rescue Exception => e
            last_exception = e
          end
        end
        raise last_exception
      end

      protected

      # max wait 64 (2**6) sec between retries
      RETRY_BACKOFF_MAX = 6

      # retry 10 times maximum
      RETRY_MAX_ATTEMPTS = 10

      # retry factor (which can be monkey-patched for quicker testing of retries)
      RETRY_DELAY_FACTOR = 1

      # ensures we are not infinitely redirected.
      MAX_REDIRECT_HISTORY = 16

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
      def http_get(path, keep_alive = true)
        uri = safe_parse_http_uri(path)
        history = []
        loop do
          @logger.debug("http_get(#{uri})")

          # keep history of live connections for more efficient redirection.
          host = uri.host
          connection = @connections[host] ||= Rightscale::HttpConnection.new(:logger => @logger, :exception => QueryFailed)

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
          if response.kind_of?(Net::HTTPServerError)
            @logger.debug("Request failed but can retry; #{response.class.name}")
            return nil
          elsif response.kind_of?(Net::HTTPNotFound)
            # EC2 and clouds which emulate it can return 404s for leaves (or for
            # user metadata) that were announced or expected but have no data.
            # it seems consistent to return emtpy for leaves which are expected
            # but were "not found".
            return ""
          elsif response.kind_of?(Net::HTTPRedirection)
            # keep history of redirects.
            history << uri.to_s
            location = response['Location']
            uri = safe_parse_http_uri(location)
            if uri.absolute?
              if history.include?(uri.to_s)
                @logger.error("Circular redirection to #{location.inspect} detected; giving up")
                return nil
              elsif history.size >= MAX_REDIRECT_HISTORY
                @logger.error("Unbounded redirection to #{location.inspect} detected; giving up")
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
            raise QueryFailed, "Request for metadata failed: #{response.class.name}"
          end
        end
      end

      # Handles some cases which raise exceptions in the URI class.
      #
      # === Parameters
      # path(String):: URI to parse
      #
      # === Return
      # uri(URI):: parsed URI
      #
      # === Raise
      # URI::InvalidURIError:: on invalid URI
      def safe_parse_http_uri(path)
        raise ArgumentError.new("URI path cannot be empty") if path.to_s.empty?
        begin
          uri = URI.parse(path)
        rescue URI::InvalidURIError => e
          # URI raises an exception for paths like "<IP>:<port>"
          # (e.g. "127.0.0.1:123") unless they also have scheme (e.g. http)
          # prefix.
          raise e if path.start_with?("http://") || path.start_with?("https://")
          uri = URI.parse("http://" + path)
          uri = URI.parse("https://" + path) if uri.port == 443
          path = uri.to_s
        end

        # supply any missing default values to make URI as complete as possible.
        if uri.scheme.nil? || uri.host.nil?
          scheme = (uri.port == 443) ? 'https' : 'http'
          uri = URI.parse("#{scheme}://#{path}")
          path = uri.to_s
        end
        if uri.path.to_s.empty?
          uri = URI.parse("#{path}/")
          path = uri.to_s
        end
        return uri
      end

    end  # HttpMetadataSource

  end  # MetadataSources

end  # RightScale
