# === Synopsis:
#   RightScale System Shutdown Utility (rs_shutdown) - (c) 2013 RightScale Inc
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
#

require 'rubygems'
require 'trollop'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'shutdown_request'))
require File.expand_path(File.join(File.dirname(__FILE__), 'command_helper'))

module RightScale

  class ShutdownClient
    include CommandHelper

    # Run
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      check_privileges
      fail("Missing required shutdown argument") unless options[:level]
      cmd = {}
      cmd[:name] = :set_shutdown_request
      cmd[:level] = options[:level]
      cmd[:immediately] = options[:immediately]
      begin
        send_command(cmd, options[:verbose]) do |response|
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

      parse do
        options.merge!(parser.parse)
        options[:level] = ::RightScale::ShutdownRequest::REBOOT if options[:reboot]
        options[:level] = ::RightScale::ShutdownRequest::STOP if options[:stop]
        options[:level] = ::RightScale::ShutdownRequest::TERMINATE if options[:terminate]
        options[:immediately] = false if options[:deferred]
      end
      options
    end

protected
    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      "rs_shutdown #{right_link_version} - RightLink's shutdown client (c) 2013 RightScale"
    end

    def usage
      Usage.scan(__FILE__)
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
