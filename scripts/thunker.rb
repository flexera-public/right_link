# === Synopsis:
#   RightScale Thunker (rs_thunk) - (c) 2011 RightScale Inc
#
#   Thunker allows you to manage custom SSH logins for non root users. It uses the rightscale
#   user and group RightScale to give privileges for authorization, managing the instance
#   under individual users' profiles. It also downloads profile tarballs containing e.g.
#   bash config.
#
## === Usage
#    rs_thunk --username USERNAME --email EMAIL [--profile DATA] [--force]
#
# === Options:
#      --username,  -u USERNAME     Authorize as RightScale user with USERNAME
#      --email,     -e EMAIL        Create audit entry saying "EMAIL logged in as USERNAME"
#      --profile,   -p DATA         Extra profile data (e.g. a URL to download)
#      --force,     -f              If profile option was specified - rewrite existing files
#
# === Examples:
#   Authorize as 'alice' with email address alice@example.com:
#     rs_thunk -u alice -e alice@example.com
#
require 'rubygems'
require 'optparse'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'
require 'right_agent/core_payload_types'
require 'right_support/net'

basedir = File.expand_path('../..', __FILE__)
require File.join(basedir, 'lib', 'instance')

module RightScale

  class Thunker
    AUDIT_REQUEST_TIMEOUT = 2 * 60  # synchronous tag requests need a long timeout

    class ThunkError < Exception
      attr_reader :code

      def initialize(msg, code=nil)
        super(msg)
        @code = code || 1
      end
    end

    # Manage individual user SSH logins
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      @log_sink = StringIO.new
      @log = Logger.new(@log_sink)
      RightScale::Log.force_logger(@log)

      username = options.delete(:username)
      email = options.delete(:email)
      profile = options.delete(:profile)
      force = options.delete(:force)

      fail(1) if missing_argument(username, "USERNAME") || missing_argument(email, "EMAIL")

      #Thunk into user's context
      orig = ENV['SSH2_ORIGINAL_COMMAND'] || ENV['SSH_ORIGINAL_COMMAND']

      if orig =~ %r{^[A-Za-z0-9_/]+scp -[ft]}
        cmd = "sudo -u #{username} #{orig}"
        access = :scp
      elsif orig =~ %r{^[A-Za-z0-9_/]+sftp-server$}
        cmd = "sudo -u #{username} #{orig}"
        access = :sftp
      elsif orig != nil && !orig.empty?
        cmd = "sudo -u #{username} #{orig}"
        access = :ssh_cmd
      else
        cmd = "sudo -i -u #{username}"
        access = :ssh_shell
      end

      client_ip = ENV['SSH_CLIENT'].split(/\s+/).first if ENV.has_key?('SSH_CLIENT')

      create_audit_entry(email, username, access, orig, client_ip)
      create_profile(username, profile, force) if profile
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

        opts.on('-p', '--profile DATA') do |data|
          options[:profile] = data
        end

        opts.on('-f', '--force') do
          options[:force] = true
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

    # Checks if argument is missing; shows error message
    #
    # === Parameters
    # parameter(String):: parameter
    # name(String):: parameter's name
    #
    # == Return
    # missing(Boolean):: true if parameter is missing
    def missing_argument(parameter, name)
      unless parameter
        STDERR.puts "Missing argument #{name}, rs_thunk --help for additional information"
        return true
      end

      return false
    end

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
        STDOUT.puts reason.message
        code = reason.code
      when String
        STDOUT.puts reason
        code = 50
      when Integer
        code = reason
      when Exception
        STDOUT.puts "Unexpected #{reason.class.name}: #{reason.message}"
        STDOUT.puts "We apologize for the inconvenience. You may try connecting as root"
        STDOUT.puts "to work around this problem, if you have sufficient privilege."
        STDERR.puts
        STDERR.puts("Debugging information:")
        STDERR.puts(@log_sink.string)
        code = 50
      else
        code = 1
      end

      puts Usage.scan(__FILE__) if options[:print_usage]
      exit(code)
    end

    def create_audit_entry(email, username, access, command, client_ip=nil)
      config_options = AgentConfig.agent_options('instance')
      listen_port = config_options[:listen_port]
      raise ArgumentError.new('Could not retrieve agent listen port') unless listen_port
      client = CommandClient.new(listen_port, config_options[:cookie])

      begin
        hostname = `hostname`.strip
      rescue Exception => e
        hostname = 'localhost'
      end

      case access
        when :scp then
          summary  = 'SSH file copy'
          detail   = "User copied files copied (scp) to/from host."
        when :sftp then
          summary  = 'SSH interactive file transfer'
          detail   = "User initiated an SFTP session."
        when :ssh_cmd
          summary  = 'SSH command'
          detail   = "User invoked an interactive program."
        when :ssh_shell
          summary  = 'SSH interactive login'
          detail   = "User connected and invoked a login shell."
      end

      detail += "\n"
      detail += "\nLogin:     #{username}@#{hostname}" if username
      detail += "\nClient IP: #{client_ip}" if client_ip
      detail += "\nCommand:   #{command}" if command

      options = {
        :name => 'audit_create_entry',
        :user_email => email,
        :summary => summary,
        :detail => detail,
        :category => RightScale::EventCategories::CATEGORY_SECURITY
      }

      client.send_command(options, false, AUDIT_REQUEST_TIMEOUT) do |res|
        fail(ThunkError.new(res.to_s)) unless res.success?
      end
    rescue Exception => e
      Log.error("#{e.class.name}:#{e.message}")
      Log.error(e.backtrace.join("\n"))
      error = SecurityError.new("Caused by #{e.class.name}: #{e.message}")
      error.set_backtrace(e.backtrace)
      fail(error)
    end

    # Downloads an archive from given path; extracts files and moves
    # them to username's home directory.
    #
    # === Parameters
    # username(String):: account's username
    # custom_data(String):: custom data, e.g. personal tarball URL
    # force(Boolean):: rewrite existing files if true; otherwise skip them
    #
    # === Return
    # extracted(Boolean):: true if profile downloaded and copied; false
    # if profile has been created earlier or error occured
    def create_profile(username, custom_data, force = false)
      home_dir = Etc.getpwnam(username).dir

      LoginUserManager.setup_profile(username, home_dir, custom_data, force)
      return true
    rescue Exception => e
      STDERR.puts
      STDERR.puts "Failed to create profile for #{username}; continuing"
      STDERR.puts "#{e.class.name}: #{e.message} - #{e.backtrace.first}"
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
      return false
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
