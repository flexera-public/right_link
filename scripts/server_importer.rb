# === Synopsis:
#   RightScale Server Import Utility (rs_connect) - (c) 2014 RightScale Inc
#
#   This utility allows an arbitrary virtual or physical machine to be
#   managed by the RightScale dashboard.
#
# === Usage
#    rs_connect --attach <url> [options]
#
#    Options:
#      --attach, -a       Attach this machine to a server
#      --force, -f        Force attachment even if server appears already connected.
#      --cloud, -c        Name of cloud in which instance is running or 'none'
#                         to indicate instance is not running in any cloud. If a
#                         cloud has already been selected during installation of
#                         RightLink then this option will override that choice.
#                         If no choice has been made then the default is 'none'.
#      --help:            Display help
#      --version:         Display version information
#
#    No options prints usage information.
#

require 'rubygems'
require 'trollop'
require 'uri'
require 'logger'
require 'net/http'
require 'fileutils'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'
require 'right_http_connection'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))

module RightScale

  class ServerImporter
    include CommandHelper
    # Exception class to use as a token that something went wrong with an HTTP query
    class QueryFailed < Exception; end

    # Exception class to use when the user data doesn't look right
    class MalformedResponse < Exception; end

    # Unsupported architecture or operating system
    class UnsupportedPlatform < Exception; end

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
          # resolve cloud name.
          cloud_file = RightScale::AgentConfig.cloud_file_path
          cloud_name = options[:cloud]
          if cloud_name.nil? && File.file?(cloud_file)
            cloud_name = File.read(cloud_file).strip
          end
          cloud_name = 'none' if cloud_name.to_s.empty?

          cloud_dir   = File.dirname(cloud_file)
          output_file = File.join(RightScale::Platform.filesystem.spool_dir, cloud_name, 'user-data.txt')
          output_dir  = File.dirname(output_file)

          if File.exist?(InstanceState::STATE_FILE) && !options[:force]
            puts "It appears this system is already managed by RightScale; cannot continue"
            puts
            puts "To override this decision, use the --force option. Please make sure you"
            puts "know what you are doing! Connecting this system to a server when it is"
            puts "already connected to another server could cause unexpected behavior in"
            puts "the RightScale dashboard, and in certain cases, data loss!"
            exit(-1)
          end

          puts "Fetching launch settings from RightScale"
          url  = options[:url]
          data = http_get(url, false)

          unless data =~ /RS_rn_id/i
            Log.error("Malformed launch settings: #{data}")
            raise MalformedResponse, "Launch settings do not look well-formed; did you specify the right URL?"
          end

          puts "Creating cloud-family hint file (#{cloud_file})"
          FileUtils.mkdir_p(cloud_dir)
          File.open(cloud_file, 'w') do |f|
            f.puts cloud_name
          end

          puts "Writing launch settings to file"
          FileUtils.mkdir_p(output_dir)
          File.open(output_file, 'w') do |f|
            f.puts data
          end

          puts "Done connecting server to RightScale. Will now attempt to start the RightLink services."
          puts "If starting of services fails, you can attempt to start them by rebooting."
          if RightScale::Platform.windows?
            puts `net start rightscale`
            exit $?.exitstatus unless $?.success?
          elsif RightScale::Platform.linux? || RightScale::Platform.darwin?
            puts `/etc/init.d/rightscale start && /etc/init.d/rightlink start`
            exit $?.exitstatus unless $?.success?
          else
            raise UnsupportedPlatform, "Starting services is not supported for this platform."
          end
          exit
        else
          puts Usage.scan(__FILE__)
          exit
      end
    rescue SystemExit => e
      raise e
    rescue Exception => e
      fail(e)
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :verbose => false, :status => false, :immediately => false, :action => :attach}

      parser = Trollop::Parser.new do 
        opt :url, "", :long => "--attach", :short => "-a", :type => String, :required => true
        opt :force
        opt :cloud, "", :type => String
        version ""
      end

      parse do
        options.merge(parser.parse)
      end
    end

protected
    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      "rs_connect #{right_link_version} - RightLink's server importer (c) 2014 RightScale"
    end

    def usage
      Usage.scan(__FILE__)
    end

    private

    def configure_logging
      Log.program_name = 'RightLink'
      Log.facility = 'user'
      Log.log_to_file_only(false)
      Log.level = Logger::INFO
      FileUtils.mkdir_p(File.dirname(InstanceState::BOOT_LOG_FILE))
      Log.add_logger(Logger.new(File.open(InstanceState::BOOT_LOG_FILE, 'a')))
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
        Log.debug("http_get(#{uri})")

        # keep history of live connections for more efficient redirection.
        host = uri.host
        connection = Rightscale::HttpConnection.new(:logger => Log, :exception => QueryFailed)

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
          Log.debug("Request failed but can retry; #{response.class.name}")
          return nil
        elsif response.kind_of?(Net::HTTPRedirection)
          # keep history of redirects.
          location = response['Location']
          uri = safe_parse_http_uri(location)
        else
          # not retryable.
          #
          # note that the EC2 metadata server is known to give malformed
          # responses on rare occasions, but the right_http_connection will
          # consider these to be 'bananas' and retry automatically (up to a
          # pre-defined limit).
          Log.error("HTTP request failed: #{response.class.name}")
          raise QueryFailed, "HTTP request failed: #{response.class.name}"
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
