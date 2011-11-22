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

      if ENV.has_key?('SSH_CLIENT')
        client_ip = ENV['SSH_CLIENT'].split(/\s+/).first
      end

      create_audit_entry(email, username, client_ip)
      create_profile(username, profile, force) if profile

      #Thunk into user's context
      home = Etc.getpwnam(username).dir
      cmd = "sudo su -l #{username}"
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

    def create_audit_entry(email, username, client_ip=nil)
      config_options = AgentConfig.agent_options('instance')
      listen_port = config_options[:listen_port]
      raise ArgumentError.new('Could not retrieve agent listen port') unless listen_port
      client = CommandClient.new(listen_port, config_options[:cookie])

      summary  = "SSH login"
      detail   = "#{email} logged in as #{username}"
      detail  += " from #{client_ip}" if client_ip

      options = {
        :name => 'audit_create_entry',
        :summary => summary,
        :category => RightScale::EventCategories::CATEGORY_SECURITY,
        :user_email => email,
        :detail => detail
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

    PROFILE_CHECKSUM = "profile.md5"

    # Downloads an archive from given path; extracts files and moves
    # them to username's home directory.
    #
    # === Parameters
    # username(String):: account's username
    # url(String):: URL to profile archive
    # force(Boolean):: rewrite existing files if true; otherwise skip them
    #
    # === Return
    # extracted(Boolean):: true if profile downloaded and copied; false
    # if profile has been created earlier or error occured
    def create_profile(username, url, force = false)
      home_dir = Etc.getpwnam(username).dir
      checksum_path = File.join('.rightscale', PROFILE_CHECKSUM)
      return false if File.exists?(File.join(home_dir, checksum_path))

      STDOUT.puts "Performing custom profile setup for #{username}"

      tmpdir = Dir.mktmpdir
      file_path = File.join(tmpdir, File.basename(url))
      if download_file(url, file_path) && extract_files(username, file_path, home_dir, force)
        save_checksum(username, file_path, checksum_path, home_dir)
        STDOUT.puts "Extracted profile for #{username}"
      end

      return true
    rescue Exception => e
      STDERR.puts "Failed to create profile for #{username}; continuing"
      STDERR.puts "#{e.class.name}: #{e.message} - #{e.backtrace.first}"
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
      return false
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir && File.exists?(tmpdir)
    end

    # Downloads a file from specified URL
    #
    # === Parameters
    # url(String):: URL to file
    # path(String):: downloaded file path
    #
    # === Return
    # downloaded(Boolean):: true if downloaded and saved successfully
    def download_file(url, path)
      client = RightSupport::Net::HTTPClient.new
      response = client.get(url, :timeout => 10)
      File.open(path, "wb") { |file| file.write(response) } unless response.empty?
      File.exists?(path)
    rescue Exception => e
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
      false
    end

    # Extracts an archive and moves files to destination directory
    # Supported archive types are:
    #   .tar.bz2 / .tbz
    #   .tar.gz / .tgz
    #   .zip
    #
    # === Parameters
    # username(String):: account's username
    # filename(String):: archive's path
    # destination_path(String):: path where extracted files should be
    # moved
    # force(Boolean):: optional; if true existing files will be
    # rewritten
    #
    # === Return
    # extracted(Boolean):: true if archive is extracted successfully
    def extract_files(username, filename, destination_path, force = false)
      escaped_filename = Shellwords.escape(filename)

      case filename
      when /(?:\.tar\.bz2|\.tbz)$/
        %x(sudo tar jxf #{escaped_filename} -C #{destination_path})
      when /(?:\.tar\.gz|\.tgz)$/
        %x(sudo tar zxf #{escaped_filename} -C #{destination_path})
      when /\.zip$/
        %x(sudo unzip -o #{escaped_filename} -d #{destination_path})
      else
        raise ArgumentError, "Don't know how to extract #{filename}'"
      end
      extracted = $?.success?

      chowned = change_owner(username, username, destination_path)
      return extracted && chowned
    end

    # Calculates MD5 checksum for specified file and saves it
    #
    # === Parameters
    # username(String):: account's username
    # target(String):: path to file
    # checksum_path(String):: relative path to checksum file
    # destination(String):: path to file where checksum should be saved
    #
    # === Return
    # nil
    def save_checksum(username, target, checksum_path, destination)
      checksum = Digest::MD5.file(target).to_s

      temp_dir = File.join(File.dirname(target), File.dirname(checksum_path))
      temp_path = File.join(File.dirname(target), checksum_path)

      FileUtils.mkdir_p(temp_dir)
      File.chmod(0771, temp_dir) # need +x to others for File.exists? => true
      File.open(temp_path, "w") { |f| f.write(checksum) }

      change_owner(username, username, temp_dir)
      %x(sudo mv #{temp_dir} #{destination})
    rescue Exception => e
      STDERR.puts "Failed to save checksum for #{username} profile"
      STDERR.puts "#{e.class.name}: #{e.message} - #{e.backtrace.first}"
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
    end

    # Changes owner of directories and files from given path
    #
    # === Parameters
    # username(String):: desired owner's username
    # group(String):: desired group name
    # path(String):: path for owner changing
    #
    # === Return
    # chowned(Boolean):: true if owner changed successfully
    def change_owner(username, group, path)
      %x(sudo chown -R #{Shellwords.escape(username)}:#{Shellwords.escape(group)} #{path})

      $?.success?
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
