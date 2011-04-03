# === Synopsis:
#   RightScale RightNet Statistics Manager (rstat) - (c) 2010 RightScale
#
#   rstat is a command line tool that displays operation statistics for a RightLink instance agent
#
# === Usage:
#    rstat [options]
#
#    options:
#      --reset, -r        As part of gathering the stats from a server also reset the stats
#      --timeout, -t SEC  Override default timeout in seconds to wait for a response from a server
#      --json, -j         Dump the stats data in JSON format
#      --version          Display version information
#      --help             Display help

require 'optparse'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'payload_types', 'lib', 'payload_types'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_utils'))
require 'rdoc/usage'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'rdoc_patch'))

module RightScale

  class StatsManager

    include Utils
    include StatsHelper

    VERSION = [0, 1, 0]

    DEFAULT_TIMEOUT = 5

    SERVERS = ["instance"]

    # Convenience wrapper
    def self.run
      begin
        c = StatsManager.new
        options = c.parse_args
        if options[:key]
          c.receive_stats(options)
        else
          options[:timeout] ||= DEFAULT_TIMEOUT
          c.request_stats(options)
        end
      rescue Exception => e
        puts "\nFailed with: #{e}\n#{e.backtrace.join("\n")}" unless e.is_a?(SystemExit)
      end
    end

    # Parse arguments
    def parse_args
      # The options specified in the command line will be collected in 'options'
      options = {:servers => [], :reset => false}

      opts = OptionParser.new do |opts|

        opts.on('-r', '--reset') do
          options[:reset] = true
        end

        opts.on('-t', '--timeout SEC') do |sec|
          options[:timeout] = sec
        end

        opts.on('-j', '--json') do
          options[:json] = true
        end

        opts.on_tail('--help') do
          RDoc::usage_from_file(__FILE__)
          exit
        end

        opts.on_tail('--version') do
          puts version
          exit
        end

      end

      begin
        opts.parse(ARGV)
      rescue Exception => e
        exit 0 if e.is_a?(SystemExit)
        fail(e.message + "\nUse 'rstat --help' for additional information")
      end

      options
    end

    # Request and display statistics from instance agents on this machine
    #
    # === Parameters
    # options(Hash):: Configuration options
    #
    # === Return
    # true:: Always return true
    def request_stats(options)
      count = 0
      SERVERS.each do |s|
        if options[:servers].empty? || options[:servers].include?(s)
          config_options = agent_options(s)
          if config_options.empty?
            puts("No #{s} running on this machine")
          else
            count += 1
            listen_port = config_options[:listen_port]
            fail("Could not retrieve #{s} listen port") unless listen_port
            client = CommandClient.new(listen_port, config_options[:cookie])
            command = {:name => :stats, :reset => options[:reset]}
            begin
              client.send_command(command, options[:verbose], options[:timeout]) { |r| display(s, r, options) }
            rescue Exception => e
              fail("Failed to retrieve #{s} stats: #{e}\n" + e.backtrace.join("\n"))
            end
          end
        end
      end
      puts("No instance agents running on this machine") if count == 0 && options[:servers].empty?
      true
    end

    protected

    # Display stats returned from server in human readable or JSON format
    #
    # === Parameters
    # server(String):: Name of server
    # result(String):: Result packet in JSON format containing stats or error
    # options(Hash):: Configuration options:
    #   :json(Boolean):: Whether to display in JSON format
    #
    # === Return
    # true:: Always return true
    def display(server, result, options)
      result = RightScale::OperationResult.from_results(JSON.load(result))
      if options[:json]
        puts result.content.to_json
      else
        if result.respond_to?(:success?) && result.success?
          puts "\n#{stats_str(result.content)}\n"
        else
          puts "\nFailed to retrieve #{server} stats: #{result.inspect}"
        end
      end
      true
    end

    # Print failure message and exit abnormally
    #
    # === Parameters
    # message(String):: Failure message
    # print_usage(Boolean):: Whether to display usage information
    #
    # === Return
    # exits the program
    def fail(message, print_usage = false)
      puts "** #{message}"
      RDoc::usage_from_file(__FILE__) if print_usage
      exit(1)
    end

    # Version information
    def version
      "rstat #{VERSION.join('.')} - RightScale RightNet Statistics Manager (c) 2010 RightScale"
    end

  end
end
