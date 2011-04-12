# === Synopsis:
#   RightScale System Rebooter (rs_shutdown) (c) 2011 RightScale
#
#   Log level manager allows setting and retrieving the RightLink agent
#   log level.
#
# === Examples:
#   Shutdown:
#     rs_shutdown --reboot --immediately
#     rs_shutdown -r -i
#     rs_shutdown --stop --deferred
#     rs_shutdown -s -d
#     rs_shutdown --terminate
#     rs_shutdown -t
#
# === Usage
#    rs_shutdown [options]
#
#    Options:
#      --reboot, -r       Request reboot.
#      --stop, -s         Request stop (boot volume is preserved).
#      --terminate, -t    Request termination (boot volume is discarded).
#      --immediately, -i  Request immediate shutdown (reboot, stop or terminate) bypassing any pending scripts and preserving instance state.
#      --deferred, -d     Request deferred shutdown (reboot, stop or terminate) pending finish of any remaining scripts (default).
#      --verbose, -v      Display debug information
#      --help:            Display help
#      --version:         Display version information
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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common', 'agent', 'shutdown_management'))

module RightScale

  class ShutdownClient

    include Utils

    VERSION = [0, 1]

    # Run
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      cmd = {}
      cmd[:name] = :set_shutdown_request
      cmd[:level] = options[:level]
      cmd[:immediately] = options[:level]
      config_options = agent_options('instance')
      listen_port = config_options[:listen_port]
      fail('Could not retrieve agent listen port') unless listen_port
      client = CommandClient.new(listen_port, config_options[:cookie])
      begin
        client.send_command(cmd, options[:verbose]) do |response|
          if response[:error]
            fail("Failed #{cmd.inspect} with #{response[:error]}")
          else
            message = response[:level]
            message += " immediately" if response[:immediately]
            puts message
          end
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
      options = { :verbose => false, :status => false, :immediately => false }

      opts = OptionParser.new do |opts|
        opts.on('-r', '--reboot') do
          options[:level] = ::RightScale::ShutdownManagement::REBOOT
        end
        opts.on('-s', '--stop') do
          options[:level] = ::RightScale::ShutdownManagement::STOP
        end
        opts.on('-t', '--terminate') do
          options[:level] = ::RightScale::ShutdownManagement::TERMINATE
        end
        opts.on('-i', '--immediately') do
          options[:immediately] = true
        end
        opts.on('-d', '--deferred') do
          options[:immediately] = false
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
        raise ArgumentError.new("Missing required shutdown argument") unless options[:level]
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
      return "rs_shutdown v#{VERSION.join('.')} - RightLink's shutdown command line utility (c) 2011 RightScale"
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
