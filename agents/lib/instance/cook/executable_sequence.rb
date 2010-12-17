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

require 'right_http_connection'
require 'process_watcher'
require 'socket'
require 'tempfile'

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'chef', 'lib', 'ohai_setup'))

#TODO TS factor this into its own source file; make it slightly less monkey-patchy (e.g. mixin)
module OpenSSL
  module SSL
    class SSLSocket
      alias post_connection_check_without_hack post_connection_check

      # Class variable. Danger! THOU SHALT NOT CAUSE 'openssl/ssl' TO RELOAD
      # nor shalt thou use this monkey patch in conjunction with Rails
      # auto-loading or class-reloading mechanisms! You have been warned...
      @@hostname_override = nil

      def self.hostname_override=(hostname_override)
        @@hostname_override = hostname_override
      end

      def post_connection_check(hostname)
        return post_connection_check_without_hack(@@hostname_override || hostname)
      end
    end
  end
end

module RightScale

  OHAI_RETRY_MIN_DELAY = 20      # Min number of seconds to wait before retrying Ohai to get the hostname
  OHAI_RETRY_MAX_DELAY = 20 * 60 # Max number of seconds to wait before retrying Ohai to get the hostname

  # Bundle sequence, includes installing dependent packages,
  # downloading attachments and running scripts in given bundle.
  # Also downloads cookbooks and run recipes in given bundle.
  # Runs in separate (runner) process.
  class ExecutableSequence
    #max wait 64 (2**6) sec between retries
    REPOSE_RETRY_BACKOFF_MAX = 6
    REPOSE_RETRY_MAX_ATTEMPTS = 10

    include EM::Deferrable

    class ReposeConnectionFailure < Exception
    end

    class ReposeServerFailure < Exception
    end

    class CookbookDownloadFailure < Exception
      def initialize(cookbook, reason)
       reason = reason.class.name unless reason.is_a?(String)
       super("#{reason} while downloading #{cookbook}")
      end
    end

    # Patch to be applied to inputs stored in core
    attr_accessor :inputs_patch

    # Failure title and message if any
    attr_reader :failure_title, :failure_message

    # Initialize sequence
    #
    # === Parameter
    # bundle(RightScale::ExecutableBundle):: Bundle to be run
    def initialize(bundle)
      @description            = bundle.to_s
      @right_scripts_cookbook = RightScriptsCookbook.new
      @scripts                = bundle.executables.select { |e| e.is_a?(RightScriptInstantiation) }
      recipes                 = bundle.executables.map    { |e| e.is_a?(RecipeInstantiation) ? e : @right_scripts_cookbook.recipe_from_right_script(e) }
      @cookbooks              = bundle.cookbooks
      @downloader             = Downloader.new
      @download_path          = InstanceConfiguration.cookbook_download_path
      @powershell_providers   = nil
      @ohai_retry_delay       = OHAI_RETRY_MIN_DELAY
      @audit                  = AuditStub.instance
      @logger                 = RightLinkLog

      #Lookup
      discover_repose_servers(bundle.repose_servers)

      # Initializes run list for this sequence (partial converge support)
      @run_list = []
      @inputs = {}
      breakpoint = DevState.breakpoint
      recipes.each do |recipe|
        if recipe.nickname == breakpoint
          @audit.append_info("Breakpoint set, running recipes up to < #{breakpoint} >")
          break
        end
        @run_list << recipe.nickname
        ChefState.deep_merge!(@inputs, recipe.attributes)
      end

      # Retrieve node attributes and deep merge in inputs
      @attributes = ChefState.attributes
      ChefState.deep_merge!(@attributes, @inputs)
    end

    # Run given executable bundle
    # Asynchronous, set deferrable object's disposition
    #
    # === Return
    # true:: Always return true
    def run
      @ok = true
      if @run_list.empty?
        # Deliberately avoid auditing anything since we did not run any recipes
        # Still download the cookbooks repos if in dev mode
        download_repos if DevState.cookbooks_path
        report_success(nil)
      else
        configure_chef
        download_attachments if @ok
        install_packages if @ok
        download_repos if @ok
        setup_powershell_providers if Platform.windows?
        check_ohai { |o| converge(o) } if @ok
      end
      true
    end

    protected

    # Configure chef so it can find cookbooks and so its logs go to the audits
    #
    # === Return
    # true:: Always return true
    def configure_chef
      # Ohai plugins path and logging.
      #
      # note that this was moved to a separate .rb file to ensure that plugins
      # path is not relative to this potentially relocatable source file.
      RightScale::OhaiSetup.configure_ohai

      # Chef logging
      Chef::Log.logger = AuditLogger.new
      Chef::Log.logger.level = RightLinkLog.level_from_sym(RightLinkLog.level)

      # Chef paths and run mode
      if DevState.use_cookbooks_path?
        Chef::Config[:cookbook_path] = DevState.cookbooks_path.reverse
        @audit.append_info("Using development cookbooks repositories path:\n\t- #{Chef::Config[:cookbook_path].join("\n\t- ")}")
      else
        Chef::Config[:cookbook_path] = (@right_scripts_cookbook.empty? ? [] : [ @right_scripts_cookbook.repo_dir ])
      end
      Chef::Config[:solo] = true

      # must set file cache path for Windows case of using remote files, templates. etc.
      platform = RightScale::RightLinkConfig[:platform]
      if platform.windows?
        file_cache_path = File.join(platform.filesystem.cache_dir, 'chef')
        Chef::Config[:file_cache_path] = file_cache_path
        Chef::Config[:cache_options][:path] = File.join(file_cache_path, 'checksums')
      end
      true
    end

    # Download attachments, update @ok
    #
    # === Return
    # true:: Always return true
    def download_attachments
      unless @scripts.all? { |s| s.attachments.empty? }
        @audit.create_new_section('Downloading attachments')
        audit_time do
          @scripts.each do |script|
            attach_dir = @right_scripts_cookbook.cache_dir(script)
            script.attachments.each do |a|
              script_file_path = File.join(attach_dir, a.file_name)
              @audit.update_status("Downloading #{a.file_name} into #{script_file_path}")
              if @downloader.download(a.url, script_file_path)
                @audit.append_info(@downloader.details)
              else
                report_failure("Failed to download attachment '#{a.file_name}'", @downloader.error)
                return true
              end
            end
          end
        end
      end
      true
    end

    # Install required software packages, update @ok
    # Always update the apt cache even if there is no package for recipes
    #
    # === Return
    # true:: Always return true
    def install_packages
      packages = []
      @scripts.each { |s| packages.push(s.packages) if s.packages && !s.packages.empty? }
      return true if packages.empty?
      packages = packages.uniq.join(' ')
      @audit.create_new_section("Installing packages: #{packages}")
      success = false
      audit_time do
        success = retry_execution('Installation of packages failed, retrying...') do
          if File.executable? '/usr/bin/yum'
            @audit.append_output(`yum install -y #{packages} 2>&1`)
          elsif File.executable? '/usr/bin/apt-get'
            ENV['DEBIAN_FRONTEND']="noninteractive"
            @audit.append_output(`apt-get install -y #{packages} 2>&1`)
          elsif File.executable? '/usr/bin/zypper'
            @audit.append_output(`zypper --no-gpg-checks -n #{packages} 2>&1`)
          else
            report_failure('Failed to install packages', 'Cannot find yum nor apt-get nor zypper binary in /usr/bin')
            return true # Not much more we can do here
          end
          $?.success?
        end
      end
      report_failure('Failed to install packages', 'Package install exited with bad status') unless success
      true
    end

    # Download required cookbooks from Repose mirror; update @ok.
    # Note: Starting with Chef 0.8, the cookbooks repositories list must be traversed in reverse
    # order to preserve the semantic of the dashboard (first repo has priority)
    #
    # === Return
    # true:: Always return true
    def download_repos
      # Skip download if in dev mode and cookbooks repos directories already have files in them
      return true unless DevState.download_cookbooks?

      @audit.create_new_section('Retrieving cookbooks') unless @cookbooks.empty?
      audit_time do
        counter = 0

        @cookbooks.each_with_index do |cookbook_sequence, i|
          local_basedir = File.join(@download_path, i.to_s)
          cookbook_sequence.positions.each do |position|
            prepare_cookbook(local_basedir, position.position,
                             position.cookbook)
          end
        end
      end

      # NB: Chef 0.8.16 requires us to contort the path ordering to preserve the semantics of
      # RS dashboard repo paths. Revisit when upgrading to >= 0.9
      @cookbooks.reverse.each_with_index do |cookbook_sequence, i|
        i = @cookbooks.size - i - 1 #adjust for reversification
        local_basedir = File.join(@download_path, i.to_s)
        cookbook_sequence.paths.reverse.each {|path|
          dir = File.expand_path(File.join(local_basedir, path))
          Chef::Config[:cookbook_path] << dir unless Chef::Config[:cookbook_path].include?(dir)
        }
      end
      true
    rescue Exception => e
      report_failure("Failed to download cookbook", "Cannot continue due to #{e.class.name}: #{e.message}.")
      RightLinkLog.debug("Failed to download cookbook due to #{e.class.name}: '#{e.message}' at\n" + e.backtrace.join("\n"))
    ensure
      OpenSSL::SSL::SSLSocket.hostname_override = nil
    end

    #
    # Download a cookbook from the mirror and extract it to the filesystem.
    #
    # === Parameters
    # local_basedir(String):: dir where all the cookbooks are going
    # relative_path(String):: subdir of basedir into which this cookbook goes
    # cookbook(Cookbook):: cookbook
    #
    # === Raise
    # Propagates exceptions raised by callees, namely CookbookDownloadFailure
    # and ReposeServerFailure
    #
    # === Return
    # true:: always returns true
    def prepare_cookbook(local_basedir, relative_path, cookbook)
      @audit.append_info("Requesting #{cookbook.name}")
      tarball = Tempfile.new("tarball")
      tarball.binmode
      result = request_cookbook(cookbook) do |response|
        response.read_body do |chunk|
          tarball << chunk
        end
      end
      tarball.close

      @audit.append_info("Success; unarchiving cookbook")

      # The local basedir is the faux "repository root" into which we extract all related
      # cookbooks in that set, "related" meaning a set of cookbooks that originally came
      # from the same Chef cookbooks repository as observed by the scraper.
      #
      # Even though we are pulling individually-packaged cookbooks and not the whole repository,
      # we preserve the position of cookbooks in the directory hierarchy such that a given cookbook
      # has the same path relative to the local basedir as the original cookbook had relative to the
      # base directory of its repository.
      #
      # This ensures we will be able to deal with future changes to the Chef merge algorithm,
      # as well as accommodate "naughty" cookbooks that side-load data from the filesystem
      # using relative paths to other cookbooks.
      root_dir = [local_basedir] + relative_path.split('/')
      root_dir = File.join(*root_dir)
      FileUtils.mkdir_p(root_dir)

      Dir.chdir(root_dir) do
        output, status = ProcessWatcher.run('tar', 'xf', tarball.path)
        if status.exitstatus != 0
          report_failure("Unknown error: #{status.exitstatus}", output)
          return
        else
          @audit.append_info(output)
        end
      end
      tarball.close(true)
      return true
    end

    # Given a sequence of preferred hostnames, lookup all IP addresses and store
    # an ordered sequence of IP addresses from which to attempt cookbook download.
    # Also build a lookup hash that maps IP addresses back to their original hostname
    # so we can perform TLS hostname verification.
    #
    # === Parameters
    # hostnames(Array):: hostnames
    #
    # === Return
    # true:: always returns true
    def discover_repose_servers(hostnames)
      @repose_idx       = 0
      @repose_ips       = []
      @repose_hostnames = {}
      @repose_failures  = 0
      hostnames = [hostnames] unless hostnames.respond_to?(:each)
      hostnames.each do |hostname|
        infos = Socket.getaddrinfo(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP)

        #Randomly permute the addrinfos of each hostname to help spread load.
        infos.shuffle.each do |info|
          ip = info[3]
          @repose_ips << ip
          @repose_hostnames[ip] = hostname
        end
      end

      true
    end

    # Find the next Repose server in the list. Perform special TLS certificate voodoo to comply
    # safely with global URL scheme.
    #
    # === Raise
    # ReposeServerFailure:: if a permanent failure happened
    #
    # === Return
    # server(Array):: [ ip address of server, HttpConnection to server ]
    def next_repose_server
      attempts = 0
      loop do
        ip         = @repose_ips[ @repose_idx % @repose_ips.size ]
        hostname   = @repose_hostnames[ip]
        @repose_idx += 1
        #TODO monkey-patch OpenSSL hostname verification
        RightLinkLog.info("Connecting to cookbook server #{ip} (#{hostname})")
        begin
          OpenSSL::SSL::SSLSocket.hostname_override = hostname

          #The CA bundle is a basically static collection of trusted certs of top-level
          #CAs. It should be provided by the OS, but because of our cross-platform nature
          #and the lib we're using, we need to supply our own. We stole curl's.
          ca_file = File.normalize_path(File.join(File.dirname(__FILE__), 'ca-bundle.crt'))

          connection = Rightscale::HttpConnection.new(:user_agent => "RightLink v#{RightLinkConfig.protocol_version}",
                                                      :logger => @logger,
                                                      :exception => ReposeConnectionFailure,
                                                      :ca_file => ca_file)
          health_check = Net::HTTP::Get.new('/')
          health_check['Host'] = hostname
          result = connection.request(:server => ip, :port => '443', :protocol => 'https',
                                      :request => health_check)
          if result.kind_of?(Net::HTTPSuccess)
            @repose_failures = 0
            return [ip, connection]
          else
            RightLinkLog.error "Health check unsuccessful: #{result.class.name}"
            unless snooze(attempts)
              RightLinkLog.error("Can't find any repose servers, giving up")
              raise ReposeServerFailure.new("too many attempts")
            end
          end
        rescue ReposeConnectionFailure => e
          RightLinkLog.error "Connection failed: #{e.message}"
          unless snooze(attempts)
            RightLinkLog.error("Can't find any repose servers, giving up")
            raise ReposeServerFailure.new("too many attempts")
          end
        end
        attempts += 1
      end
    end

    def snooze(attempts)
      if attempts > REPOSE_RETRY_MAX_ATTEMPTS
        false
      else
        @repose_failures = [@repose_failures + 1, REPOSE_RETRY_BACKOFF_MAX].min
        sleep (2**@repose_failures)
        true
      end
    end

    # Request a cookbook from the Repose mirror, performing retry as necessary. Block
    # until the cookbook has been downloaded, or until permanent failure has been
    # determined.
    #
    # === Parameters
    # cookbook(RightScale::Cookbook):: the cookbook to download
    #
    # === Block
    # If the request succeeds this method will yield, passing
    # the HTTP response object as its sole argument.
    #
    # === Raise
    # CookbookDownloadFailure:: if a permanent failure happened
    # ReposeServerFailure:: if no Repose server could be contacted
    #
    # === Return
    # true:: always returns true
    def request_cookbook(cookbook)
      @repose_connection ||= next_repose_server
      cookie = Object.new
      result = cookie
      attempts = 0

      while result == cookie
        RightLinkLog.info("Requesting #{cookbook}")
        request = Net::HTTP::Get.new("/cookbooks/#{cookbook.hash}")
        request['Cookie'] = "repose_ticket=#{cookbook.token}"
        request['Host'] = @repose_connection.first

        @repose_connection.last.request(
            :protocol => 'https', :server => @repose_connection.first, :port => '443',
            :request => request) do |response|
          if response.kind_of?(Net::HTTPSuccess)
            @repose_failures = 0
            yield response
            result = true
          elsif response.kind_of?(Net::HTTPServerError) || response.kind_of?(Net::HTTPNotFound)
            RightLinkLog.warn("Request failed - #{response.class.name} - retry")
            if snooze(attempts)
              @repose_connection = next_repose_server
            else
              RightLinkLog.error("Request failed - too many attempts, giving up")
              result = CookbookDownloadFailure.new(cookbook, "too many attempts")
              next
            end
          else
            RightLinkLog.error("Request failed - #{response.class.name} - give up")
            result = CookbookDownloadFailure.new(cookbook, response)
          end
        end
        attempts += 1
      end

      raise result if result.kind_of?(Exception)
      return true
    end

    # Create Powershell providers from cookbook repos
    #
    #
    # === Return
    # true:: Always return true
    def setup_powershell_providers
      dynamic_provider = DynamicPowershellProvider.new
      dynamic_provider.generate_providers(Chef::Config[:cookbook_path])
      @powershell_providers = dynamic_provider.providers
    end

    # Checks whether Ohai is ready and calls given block with it
    # if that's the case otherwise schedules itself to try again
    # indefinitely
    #
    # === Block
    # Given block should take one argument which corresponds to
    # ohai instance
    #
    # === Return
    # true:: Always return true
    def check_ohai
      ohai = Ohai::System.new
      ohai.require_plugin('os')
      ohai.require_plugin('hostname')
      if ohai[:hostname]
        yield(ohai)
      else
        RightLinkLog.warn("Could not determine node name from Ohai, will retry in #{@ohai_retry_delay}s...")
        EM.add_timer(@ohai_retry_delay) { check_ohai }
        @ohai_retry_delay = [ 2 * @ohai_retry_delay, OHAI_RETRY_MAX_DELAY ].min
      end
      true
    end

    # Chef converge
    #
    # === Parameters
    # ohai(Ohai):: Ohai instance to be used by Chef
    #
    # === Return
    # true:: Always return true
    def converge(ohai)
      @audit.create_new_section('Converging')
      @audit.append_info("Run list: #{@run_list.join(', ')}")
      attribs = { 'recipes' => @run_list }
      attribs.merge!(@attributes) if @attributes
      c = Chef::Client.new
      c.ohai = ohai
      begin
        audit_time do
          c.json_attribs = attribs
          c.run_solo
        end
      rescue Exception => e
        report_failure('Chef converge failed', chef_error(e))
        RightLinkLog.debug("Chef failed with '#{e.message}' at\n" + e.backtrace.join("\n"))
      ensure
        # terminate the powershell providers
        # terminate the providers before the node server as the provider term scripts may still use the node server
        if @powershell_providers
          @powershell_providers.each do |p|
            begin
              p.terminate
            rescue Exception => e
              RightLinkLog.debug("Error terminating '#{p.inspect}': '#{e.message}' at\n #{e.backtrace.join("\n")}")
            end
          end
        end

        # kill the chef node provider
        RightScale::Windows::ChefNodeServer.instance.stop rescue nil if Platform.windows?
      end
      report_success(c.node) if @ok
      true
    end

    # Initialize inputs patch and report success
    #
    # === Parameters
    # node(ChefNode):: Chef node used to converge, can be nil (patch is empty in this case)
    #
    # === Return
    # true:: Always return true
    def report_success(node)
      ChefState.merge_attributes(node.attribute) if node
      patch = ChefState.create_patch(@inputs, ChefState.attributes)
      # We don't want to send back new attributes (ohai etc.)
      patch[:right_only] = {}
      @inputs_patch = patch
      EM.next_tick { succeed }
      true
    end

    # Set status with failure message and audit it
    #
    # === Parameters
    # title(String):: Title used to update audit status
    # msg(String):: Failure message
    #
    # === Return
    # true:: Always return true
    def report_failure(title, msg)
      @ok = false
      @failure_title = title
      @failure_message = msg

      # note that the errback handler is expected to audit the message based on
      # the preserved title and message and so we don't audit it here.
      EM.next_tick { fail }
      true
    end

    # Wrap chef exception with explanatory information and show
    # context of failure
    #
    # === Parameters
    # e(Exception):: Exception raised while executing Chef recipe
    #
    # === Return
    # msg(String):: Human friendly error message
    def chef_error(e)
      if e.is_a?(RightScale::Exceptions::Exec)
        msg = "An external command returned an error during the execution of Chef:\n\n"
        msg += e.message
        msg += "\n\nThe command was run from \"#{e.path}\"" if e.path
      elsif e.is_a?(::Chef::Exceptions::ValidationFailed) && (e.message =~ /Option action must be equal to one of:/)
        msg = "[chef] recipe references an action that does not exist.  #{e.message}"
      elsif e.is_a?(::NameError) && (missing_action_match = /Cannot find Action\S* for action_(\S*)\s*Original exception: NameError: uninitialized constant Chef::Resource::Action\S*/.match(e.message)) && missing_action_match[1]
        msg = "[chef] recipe references the action <#{missing_action_match[1]}> which is missing an implementation"
      else
        msg = "An error occurred during the execution of Chef. The error message was:\n\n"
        msg += e.message
        file, line, meth = e.backtrace[0].scan(/(.*):(\d+):in `(\w+)'/).flatten
        line_number = line.to_i
        if file && line && (line_number.to_s == line)
          if file[0..InstanceConfiguration.cookbook_download_path.size - 1] == InstanceConfiguration::cookbook_download_path
            path = "[COOKBOOKS]/" + file[InstanceConfiguration.cookbook_download_path.size..file.size]
          else
            path = file
          end
          msg += "\n\nThe error occurred line #{line} of #{path}"
          msg += " in method '#{meth}'" if meth
          context = ""
          if File.readable?(file)
            File.open(file, 'r') do |f|
              lines = f.readlines
              lines_count = lines.size
              if lines_count >= line_number
                upper = [lines_count, line_number + 2].max
                padding = upper.to_s.size
                context += context_line(lines, line_number - 2, padding)
                context += context_line(lines, line_number - 1, padding)
                context += context_line(lines, line_number, padding, '*')
                context += context_line(lines, line_number + 1, padding)
                context += context_line(lines, line_number + 2, padding)
              end
            end
          end
          msg += " while executing:\n\n#{context}" unless context.empty?
        end
      end
      msg
    end

    # Format a single line for the error context, return empty string
    # if given index is negative or greater than the lines array size
    #
    # === Parameters
    # lines(Array):: Lines of text
    # index(Integer):: Index of line that should be formatted for context
    # padding(Integer):: Number of character to pad line with (includes prefix)
    # prefix(String):: Single character string used to prefix line
    #                  use line number if not specified
    def context_line(lines, index, padding, prefix=nil)
      return '' if index < 1 || index > lines.size
      margin = prefix ? prefix * index.to_s.size : index.to_s
      "#{margin}#{' ' * ([padding - margin.size, 0].max)} #{lines[index - 1]}"
    end

    # Retry executing given block given number of times
    # Block should return true when it succeeds
    #
    # === Parameters
    # retry_message(String):: Message to audit before retrying
    # times(Integer):: Number of times block should be retried before giving up
    #
    # === Block
    # Block to be executed
    #
    # === Return
    # success(Boolean):: true if execution was successful, false otherwise.
    def retry_execution(retry_message, times=InstanceConfiguration::MAX_PACKAGES_INSTALL_RETRIES)
      count = 0
      success = false
      begin
        count += 1
        success = yield
        @audit.append_info("\n#{retry_message}\n") unless success || count > times
      end while !success && count <= times
      success
    end

    # Audit startup time and duration of given action
    #
    # === Block
    # Block whose execution should be timed
    #
    # === Return
    # res(Object):: Result returned by given block
    def audit_time
      start_time = Time.now
      @audit.append_info("Starting at #{start_time}")
      res = yield
      @audit.append_info("Duration: #{'%.2f' % (Time.now - start_time)} seconds\n\n")
      res
    end

  end

end
