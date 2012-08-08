# === Synopsis:
#   RightScale System Shutdown Utility (rs_shutdown) - (c) 2011 RightScale Inc
#
#   This utility allows the given system to be shutdown or rebooted.
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

require 'rubygems'
require 'trollop'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'shutdown_request'))

module RightScale

  class ShutdownClient

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
      cmd[:immediately] = options[:immediately]
      config_options = AgentConfig.agent_options('instance')
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
      options = { :verbose => false, :status => false, :immediately => false }
      parser = Trollop::Parser.new do
        opt :reboot
        opt :stop
        opt :terminate
        opt :immediately
        opt :deferred
        opt :verbose
        version ""
        conflicts :deferred, :immediately
      end

      begin
        options.merge!(parser.parse)
        options[:level] = ::RightScale::ShutdownRequest::REBOOT if options[:reboot]
        options[:level] = ::RightScale::ShutdownRequest::STOP if options[:stop]
        options[:level] = ::RightScale::ShutdownRequest::TERMINATE if options[:terminate]
        options[:immediately] = false if options[:deferred]
        raise ArgumentError, "Missing required shutdown argument" unless options[:level]
      rescue Trollop::VersionNeeded
        puts version
        succeed
      rescue Trollop::HelpNeeded
        puts Usage.scan(__FILE__)
        exit
      rescue SystemExit => e
        raise e
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
    # reason(String|Exception):: Error message or exception, default to nil (no message printed)
    # print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(reason=nil, print_usage=false)
      case reason
      when Errno::EACCES
        STDERR.puts "** #{reason.message}"
        STDERR.puts "** Try elevating privilege (sudo/runas) before invoking this command."
        code = 2
      when Exception
        STDERR.puts "** #{reason.message}"
        code = 1
      else
        STDERR.puts "** #{reason}" if reason
        code = 1
      end

      puts Usage.scan(__FILE__) if print_usage
      exit(code)
    end
    
    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      gemspec = eval(File.read(File.join(File.dirname(__FILE__), '..', 'right_link.gemspec')))
      "rs_shutdown #{gemspec.version} - RightLink's shutdown client (c) 2011 RightScale"
    end

  end # ShutdownClient

end # RightScale

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
