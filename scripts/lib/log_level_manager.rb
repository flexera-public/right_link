# === Synopsis:
#   RightScale Log Level Manager (rs_log_level)
#   (c) 2009 RightScale
#
#   Log level manager allows setting and retrieving the RightLink agent
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
#    rs_set_log_level [--log-level, -l debug|info|warn|error|fatal]
#
#    Options:
#      --log-level, -l LVL  Set log level of RightLink agent
#      --verbose, -v        Display debug information
#      --help:              Display help
#      --version:           Display version information
#
#    No options prints the current RightLink agent log level
#
$:.push(File.dirname(__FILE__))

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'rdoc_patch'
require 'agent_utils'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'actors', 'lib', 'agent_manager'))

module RightScale

  class LogLevelManager

    include Utils

    VERSION = [0, 1]

    # Set log level
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      level = options[:level]
      cmd = { :name => (level ? 'set_log_level' : 'get_log_level') }
      cmd[:level] = level.to_sym if level
      config_options = agent_options('instance')
      listen_port = config_options[:listen_port]
      fail('Could not retrieve agent listen port') unless listen_port
      client = CommandClient.new(listen_port, config_options[:cookie])
      begin
        client.send_command(cmd, options[:verbose]) do |lvl|
          puts "Agent log level: #{lvl.to_s.upcase}"
        end
      rescue Exception => e
        fail(e.message)
      end
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :verbose => false }

      opts = OptionParser.new do |opts|

        opts.on('-l', '--log-level LEVEL') do |l|
          fail("Invalid log level '#{l}'") unless AgentManager::LEVELS.include?(l.to_sym)
          options[:level] = l
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
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
    # ver(String):: Version information
    def version
      ver = "run_log_level #{VERSION.join('.')} - RightLink's dynamic log level manager (c) 2009 RightScale"
    end

  end
end

#
# Copyright (c) 2009 RightScale Inc
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
