# === Synopsis:
#   RightScale Log Level Manager (rs_log_level) - (c) 2009-2014 RightScale Inc
#
#   Log level manager allows setting and retrieving the RightLink agent and Chef/RightScript
#   log level.
#
# === Examples:
#   Retrieve log level:
#     rs_log_level
#
#   Set log level to debug:
#     rs_log_level --log-level debug
#     rs_log_level -l debug
#
# === Usage
#    rs_log_level [--log-level, -l debug|info|warn|error|fatal]
#
#    Options:
#      --log-level, -l LVL  Set log level(for Chef/RightScript by default)
#      --agent, -a          Set/get log level of RightLink agent
#      --verbose, -v        Display debug information
#      --help:              Display help
#      --version:           Display version information
#
#    No options prints the current Chef/RightScript log level
#

require 'right_agent/scripts/log_level_manager'
require 'trollop'
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'tagger'))

module RightScale

  class RightLinkLogLevelManager < LogLevelManager
    include CommandHelper

    LOG_LEVEL_TAG = "rs_agent_dev:log_level"

    # Convenience wrapper for creating and running log level manager
    #
    # === Return
    # true:: Always return true
    def self.run
      m = RightLinkLogLevelManager.new

      options = m.parse_args
      m.check_privileges
      m.manage(options)

      if options[:level] =~ /debug/i && !RightScale::Platform.windows?
        puts
        puts "NOTE: RightLink is now logging with syslog severity 'debug', but your system"
        puts "      log daemon may discard these messages. If debug messages do not appear,"
        puts "      review your syslog configuration and restart the daemon."
      end
    end

    def manage(options)
      return super(options) if options[:agent]
      cmd = options[:level] ? { :name => :add_tag } : { :name => :get_tags }
      cmd[:tag] = "#{LOG_LEVEL_TAG}=#{options[:level]}" if options[:level]
      res = send_command(cmd, options[:verbose], Tagger::TAG_REQUEST_TIMEOUT)
      case cmd[:name]
      when :get_tags
        fail("Getting log level failed: #{res.inspect}") unless res.kind_of?(Array)
        log_level_tag = res.detect { |tag| tag.start_with?(LOG_LEVEL_TAG) }
        level = log_level_tag ? log_level_tag.split("=").last : send_command({ :name => 'get_log_level' }, options[:verbose], 5)
        write_output("Chef/RightScript log level: #{level.to_s.upcase}")
      when :add_tag
        r = serialize_operation_result(res)
        fail("Setting log level failed: #{r.inspect}") unless r.kind_of?(OperationResult)
        fail("Setting log level failed: #{r.content}") unless r.success?
        write_output("Successfully set log level to #{options[:level]}")
      end
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :agent_name => 'instance', :verbose => false }

      parser = Trollop::Parser.new do
        opt :level, "", :type => String, :long => "--log-level", :short => "-l"
        opt :agent
        opt :verbose
        version ""
      end

      parse do
        options.merge!(parser.parse)
        if options[:level]
          fail("Invalig log level '#{options[:level]}'") unless AgentManager::LEVELS.include?(options[:level].to_sym)
        end
        options
      end
    end

protected

    # Writes to STDOUT (and a placeholder for spec mocking).
    #
    # === Parameters
    # @param [String] message to write
    def write_output(message)
      STDOUT.puts(message)
    end

    # Writes to STDERR (and a placeholder for spec mocking).
    #
    # === Parameters
    # @param [String] message to write
    def self.write_error(message)
      STDERR.puts(message)
    end

    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      "rs_log_level #{right_link_version} - RightLink's log level (c) 2014 RightScale"
    end

    def usage
      Usage.scan(__FILE__)
    end

  end
end

#
# Copyright (c) 2009-2011 RightScale Inc
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
