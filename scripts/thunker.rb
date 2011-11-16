# === Synopsis:
#   RightScale Thunker (rs_thunk) - (c) 2011 RightScale Inc
#
#   Thunker allows you to manage custom SSH logins for non root users. It uses default user
#   RightScale and also group RightScale to give priveleges for authorization, managing the instance
#   under individual users profile and download the tarballs with local user's bash configuration.
#
# === Examples:
#   Authorize as RightScale user 'username':
#     rs_thunk --username username
#     rs_thunk -e username
#
# === Usage
#    rs_thunk (--username, e USERNAME | --email, -e EMAIL | --profile, -p URL)
#
#    Options:
#      --username,  -u USERNAME     Authorize as RiaghtScale user with USERNAME
#      --email,     -e EMAIL        Create audit entry saying "EMAIL logged in as USERNAME"
#      --profile,   -p URL          If profile URL was specified - download file from profile URL
#

require 'rubygems'
require 'optparse'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

module RightScale

  class Thunker

    class ThunkError < Exception
      attr_reader :code

      def initialize(msg, code=nil)
        super(msg)
        @code = code || 1
      end
    end

    # Manage individual user SSH logings
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      RightScale::Log.force_logger(Logger.new(STDERR))
      username, email, profile = options.delete(:username), options.delete(:email), options.delete(:profile)
      unless username
        STDERR.puts "Missing argument USERNAME, rs_thunk --help for additional information"
        fail(1)
      end
      STDOUT.puts "# => WIP: We're going to upate AuditEntries for #{email} here" if email
      STDOUT.puts "# => WIP: We're going to download your profile tarball from #{profile} here" if profile
      cmd = "cd /home/#{username}; sudo su #{username}"
      Kernel.exec(cmd)
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = {}
      opts = OptionParser.new do |opts|
        opts.on('-u', '--username USERNAME') do |username|
          options[:username] = username
        end

        opts.on('-e', '--email EMAIL') do |email|
          options[:email] = email
        end

        opts.on('-p', '--profile PROFILE') do |profile|
          options[:profile] = profile
        end
      end

      opts.on_tail('--help') do
         puts Usage.scan(__FILE__)
         succeed
      end

      begin
        opts.parse!(ARGV)
      rescue Exception => e
        STDERR.puts e.message + "\nUse rs_thunk --help for additional information"
        fail(1)
      end
      options
    end

protected
    # Exit with success.
    #
    # === Return
    # R.I.P. does not return
    def succeed
      exit(0)
    end

    # Print error on console and exit abnormally
    #
    # === Parameter
    # msg(String):: Error message, default to nil (no message printed)
    # print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(reason=nil, options={})
      case reason
      when ThunkError
        STDERR.puts reason.message
        code = reason.code
      when Exception
        STDERR.puts reason.message
        code = 50
      when String
        STDERR.puts reason
        code = 50
      when Integer
        code = reason
      else
        code = 1
      end

      puts Usage.scan(__FILE__) if options[:print_usage]
      exit(code)
    end

  end # Thunker

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
