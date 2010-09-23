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

require File.join(File.dirname(__FILE__), 'spec_helper')
require 'fileutils'
require 'tmpdir'

module RightScale
  class FetchRunner

    FETCH_TEST_SOCKET_ADDRESS = '127.0.0.1'
    FETCH_TEST_SOCKET_PORT = 55555
    FETCH_TEST_TIMEOUT_SECS = 30  # test runs a bit slow in Windows

    # ensure uniqueness of handler to avoid confusion.
    raise "#{FetchMockServerInputHandler.name} is already defined" if defined?(FetchMockServerInputHandler)

    module FetchMockServerInputHandler
      def initialize(handler)
        @handler = handler
      end

      def receive_data(data)
        @handler.call(data, self)
        true
      end
    end

    def initialize
      @log_file_name = nil
      @log_file = nil
      @logger = nil
    end

    attr_accessor :logger

    # true if debugging.
    def is_debug?
      return !!ENV['DEBUG']
    end

    # Setup log for test.
    def setup_log
      @log_file_name = File.normalize_path(File.join(Dir.tmpdir, "#{File.basename(__FILE__, '.rb')}_#{Time.now.strftime("%Y-%m-%d-%H%M%S")}.log"))
      @log_file = File.open(@log_file_name, 'w')
      @logger = Logger.new(@log_file)
      @logger.level = is_debug? ? Logger::DEBUG : Logger::INFO
      return @logger
    end

    # Teardown log.
    def teardown_log
      if @logger
        @logger = nil
        @log_file.close rescue nil
        @log_file = nil
        if ENV['RS_LOG_KEEP']
          puts "Log saved to \"#{@log_file_name}\""
        else
          FileUtils.rm_f(@log_file_name)
        end
        @log_file_name = nil
      end
    end

    # Runs the metadata provider after starting a server to respond to fetch
    # requests.
    #
    # === Parameters
    # metadata_provider(MetadataProvider):: metadata_provider to test
    #
    # metadata_formatter(MetadataFormatter):: metadata_formatter to test
    #
    # block(callback):: handler for server requests
    #
    # === Returns
    # metadata(Hash):: flat metadata hash
    def run_fetcher(metadata_provider, metadata_formatter, &block)
      server = nil
      done = false
      last_exception = nil
      flat_metadata = nil
      EM.run do
        begin
          server = EM.start_server(FETCH_TEST_SOCKET_ADDRESS,
                                   FETCH_TEST_SOCKET_PORT,
                                   FetchMockServerInputHandler,
                                   block)
          EM.defer do
            begin
              tree_metadata = metadata_provider.metadata
              flat_metadata = metadata_formatter.format_metadata(tree_metadata)
            rescue Exception => e
              last_exception = e
            end
            done = true
          end
          timer = EM.add_periodic_timer(0.1) do
            if done
              timer.cancel
              timer = nil
              EM.next_tick do
                EM.stop_server(server)
                server = nil
                EM.stop
              end
            end
          end
          EM.add_timer(FETCH_TEST_TIMEOUT_SECS) { raise "timeout" }
        rescue Exception => e
          last_exception = e
        end
      end

      # reraise with full backtrace for debugging purposes. this assumes the
      # exception class accepts a single string on construction.
      if last_exception
        message = "#{last_exception.message}\n#{last_exception.backtrace.join("\n")}"
        if last_exception.class == ArgumentError
          raise ArgumentError, message
        else
          begin
            raise last_exception.class, message
          rescue ArgumentError
            # exception class does not support single string construction.
            message = "#{last_exception.class}: #{message}"
            raise message
          end
        end
      end

      return flat_metadata
    end

    EC2_METADATA_REQUEST_REGEXP = /GET \/latest\/meta-data\/(.*) /

    # Extracts the root-relative path of the requested metadata from the GET
    # parameter.
    #
    # === Parameters
    # data(String):: raw data from REST request
    #
    # === Returns
    # metadata_path(String):: request path or empty for root or nil
    def get_metadata_request_path(data)
      match_data = EC2_METADATA_REQUEST_REGEXP.match(data)
      return match_data ? match_data[1] : nil
    end

    # Extracts the correct response from the valid metadata tree based on the
    # GET parameter.
    #
    # === Parameters
    # data(String):: raw data from REST request
    # metadata(Hash):: metadata for responses
    #
    # === Returns
    # out(String):: response or empty
    def get_metadata_response(data, metadata)
      # extract requested metadata path.
      if (sub_path = get_metadata_request_path(data))
        # walk tree matching path elements.
        while not sub_path.empty?
          offset = sub_path.index('/')
          if offset
            child_name = sub_path[0,offset]
            sub_path = sub_path[(offset + 1)..-1]
          else
            child_name = sub_path
            sub_path = ""
          end
          return "" unless metadata.respond_to?(:has_key?)

          unless child_metadata = metadata[child_name]
            # allow partial match of child name followed by equals.
            metadata.each do |key, value|
              if 0 == key.index(child_name + '=')
                child_metadata = value
                break
              end
            end
          end
          return "" unless child_metadata
          metadata = child_metadata
        end

        # right-hand metadata is either a string or a subtree
        if metadata.respond_to?(:has_key?)
          listing = []
          metadata.keys.sort.each do |key|
            if metadata[key].respond_to?(:has_key?)
              listing << key + '/'
            else
              listing << key
            end
          end
          return listing.join("\n")
        else
          # FIX: either EM or cURL appears to have a problem with small
          # responses (less than 6 characters) or else small responses don't get
          # flushed for some reason. need to understand the reason that the cURL
          # client considers the response empty and returns exit code 52. this
          # code is only used for testing so it is not critical.
          while metadata.length < 6
            metadata += "\n"  # extra newlines should get stripped
          end
          return metadata  # simple string value
        end
      end

      # invalid request, empty response.
      return ""
    end
  end
end
