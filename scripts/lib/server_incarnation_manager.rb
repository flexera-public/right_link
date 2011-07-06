# === Synopsis:
#   RightScale Server Incarnation Manager (rs_server) (c) 2011 RightScale
#
#   This utility allows an arbitrary virtual or physical machine to be
#   attached to a RightScale server, allowing existing machines to be
#   used with the RightScale dashboard.
#
# === Usage
#    rs_server --attach <url> [options]
#
#    Options:
#      --attach, -a       Attach this machine to a server
#      --help:            Display help
#      --version:         Display version information
#
#    No options prints usage information.
#
$:.push(File.dirname(__FILE__))

require 'optparse'
require 'uri'
require 'fileutils'
require 'logger'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'net/http'

require 'right_http_connection'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))
require 'rdoc_patch'

module RightScale

  class ServerIncarnationManager
    VERSION = [0, 1]

    # Run
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      configure_logging

      case options[:action]
        when :attach
          url  = options[:url]
          cloud_dir   = File.dirname(cloud_file)
          output_file = File.join(RightScale::Platform.filesystem.spool_dir, 'none', 'user-data.txt')
          output_dir  = File.dirname(output_file)

          puts "Fetching launch settings from RightScale"
          data = http_get(url, false)

          cloud_file  = File.join(RightScale::Platform.filesystem.right_scale_state_dir, 'cloud')
          puts "Creating cloud-family hint file (#{cloud_file})"
          FileUtils.mkdir_p(cloud_dir)
          File.open(cloud_file, 'w') do |f|
            f.puts 'none'
          end

          puts "Writing launch settings to file"
          FileUtils.mkdir_p(output_dir)
          File.open(output_file, 'w') do |f|
            f.puts data
          end

          puts "Done! Please reboot to continue transforming this machine into"
          puts "a RightScale-managed server."
        else
          RDoc::usage_from_file(__FILE__)
          exit
      end
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :verbose => false, :status => false, :immediately => false }

      opts = OptionParser.new do |opts|
        opts.on('-a', '--attach URL') do |url|
          options[:action] = :attach
          options[:url] = url
        end
      end

      opts.on_tail('--version') do
        puts version
        exit
      end

      opts.on_tail('--help') do
        RDoc::usage_from_file(__FILE__)
        exit
      end

      begin
        opts.parse!(ARGV)
        if options[:action] == :attach && !options[:url]
          raise ArgumentError, "Missing required shutdown argument"
        end
      rescue Exception => e
        puts e.message + "\nUse --help for additional information"
        exit(1)
      end
      options
    end

protected

    # Print error on console and exit abnormally
    #
    # === Parameter
    # msg(String):: Error message, default to nil (no message printed)
    # print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      RDoc::usage_from_file(__FILE__) if print_usage
      exit(1)
    end

    # Version information
    #
    # === Return
    # version(String):: Version information
    def version
      return "rs_server v#{VERSION.join('.')} - RightLink's server incarnation command line utility (c) 2011 RightScale"
    end

    private

    def configure_logging
      RightLinkLog.program_name = 'RightLink'
      RightLinkLog.log_to_file_only(false)
      RightLinkLog.level = Logger::INFO
      FileUtils.mkdir_p(File.dirname(InstanceState::BOOT_LOG_FILE))
      RightLinkLog.add_logger(Logger.new(File.open(InstanceState::BOOT_LOG_FILE, 'a')))
      RightLinkLog.add_logger(Logger.new(STDOUT))
    end

    # Exception class to use as a token that something went wrong with an HTTP query
    class QueryFailed < Exception; end

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
        RightLinkLog.debug("http_get(#{uri})")

        # keep history of live connections for more efficient redirection.
        host = uri.host
        connection = Rightscale::HttpConnection.new(:logger => RightLinkLog, :exception => QueryFailed)

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
          RightLinkLog.debug("Request failed but can retry; #{response.class.name}")
          return nil
        elsif response.kind_of?(Net::HTTPRedirection)
          # keep history of redirects.
          history << uri.to_s
          location = response['Location']
          uri = safe_parse_http_uri(location)
          if uri.absolute?
            if history.include?(uri.to_s)
              RightLinkLog.error("Circular redirection to #{location.inspect} detected; giving up")
              return nil
            elsif history.size >= MAX_REDIRECT_HISTORY
              RightLinkLog.error("Unbounded redirection to #{location.inspect} detected; giving up")
              return nil
            else
              # redirect and continue in loop.
              RightLinkLog.debug("Request redirected to #{location.inspect}: #{response.class.name}")
            end
          else
            # can't redirect without an absolute location.
            RightLinkLog.error("Unable to redirect to metadata server location #{location.inspect}: #{response.class.name}")
            return nil
          end
        else
          # not retryable.
          #
          # note that the EC2 metadata server is known to give malformed
          # responses on rare occasions, but the right_http_connection will
          # consider these to be 'bananas' and retry automatically (up to a
          # pre-defined limit).
          RightLinkLog.error("Request for metadata failed: #{response.class.name}")
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
  end

end

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
