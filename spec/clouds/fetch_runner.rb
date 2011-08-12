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

require File.join(File.dirname(__FILE__), 'spec_helper')
require 'fileutils'
require 'tmpdir'
require 'webrick'

module RightScale
  class FetchRunner

    FETCH_TEST_SOCKET_ADDRESS = '127.0.0.1'
    FETCH_TEST_SOCKET_PORT = 55555
    FETCH_TEST_TIMEOUT_SECS = 60

    class MockHTTPServer < WEBrick::HTTPServer
      def initialize(options={}, &block)
        super(options.merge(:Port => FETCH_TEST_SOCKET_PORT, :AccessLog => []))

        # mount servlets via callback
        block.call(self)

        #Start listening for HTTP in a separate thread
        Thread.new do
          self.start()
        end
      end

      # Recursively mounts the servlets for the metadata in the given tree using
      # the given base path as a starting point.
      #
      # === Parameters
      # metadata(Hash or String):: metadata to mount
      #
      # metadata_path(Array):: array of path elements for current metadata path
      def recursive_mount_metadata(metadata, metadata_path)
        path = get_metadata_request_path(metadata_path)
        out = get_metadata_response(metadata)
        mount_proc(path) { |request, response| response.body = out }

        # recursion, if metadata is a hash.
        if metadata.respond_to?(:has_key?)
          metadata.each do |key, value|
            # equals has a special meaning and is not included in metadata path.
            if equals_offset = key.index('=')
              key = key[0, equals_offset]
            end
            metadata_path << key
            recursive_mount_metadata(value, metadata_path)
            metadata_path.pop
          end
        end
      end

      # Gets the root-relative path of the requested metadata from the path
      # element array.
      #
      # === Parameters
      # metadata_path(Array):: array of path elements for current metadata path
      #
      # === Returns
      # metadata_path(String):: request path or empty for root or nil
      def get_metadata_request_path(metadata_path)
         return "/" + metadata_path.join("/")
      end

      # Generates the correct response from the given metadata.
      #
      # === Parameters
      # metadata(Hash or String):: metadata to mount
      #
      # === Returns
      # out(String):: valid response
      def get_metadata_response(metadata)
        if metadata.respond_to?(:has_key?)
          listing = []
          metadata.keys.sort.each do |key|
            value = metadata[key]
            if value.respond_to?(:has_key?)
              listing << key + '/'
            else
              listing << key
            end
          end
          return listing.join("\n")
        end
        return metadata
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
      unless defined?(@@log_file_base_name)
        @@log_file_base_name = File.normalize_path(File.join(Dir.tmpdir, "#{File.basename(__FILE__, '.rb')}_#{Time.now.strftime("%Y-%m-%d-%H%M%S")}"))
        @@log_file_index = 0
      end
      @@log_file_index += 1
      @log_file_name = "#{@@log_file_base_name}_#{@@log_file_index}.log"
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
    def run_fetcher(*args, &block)
      server = nil
      done = false
      last_exception = nil
      results = []
      EM.run do
        begin
          server = MockHTTPServer.new({:Logger => @logger}, &block)
          EM.defer do
            begin
              args.each do |metadata_provider|
                results << metadata_provider.build_metadata
              end
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
                EM.stop
              end
            end
          end
          EM.add_timer(FETCH_TEST_TIMEOUT_SECS) { @logger.error("timeout"); raise "timeout" }
        rescue Exception => e
          last_exception = e
        end
      end

      # stop server, if any.
      (server.shutdown rescue nil) if server

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

      return 1 == results.size ? results[0] : results
    end
  end
end
