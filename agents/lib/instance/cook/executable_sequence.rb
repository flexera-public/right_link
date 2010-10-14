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

module RightScale

  OHAI_RETRY_MIN_DELAY = 20      # Min number of seconds to wait before retrying Ohai to get the hostname
  OHAI_RETRY_MAX_DELAY = 20 * 60 # Max number of seconds to wait before retrying Ohai to get the hostname

  # Bundle sequence, includes installing dependent packages,
  # downloading attachments and running scripts in given bundle.
  # Also downloads cookbooks and run recipes in given bundle.
  # Runs in separate (runner) process.
  class ExecutableSequence

    include EM::Deferrable
    include ProcessWatcher

    class ReposeConnectionException < Exception
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
      @repose_server          = bundle.repose_server
      @downloader             = Downloader.new
      @download_path          = InstanceConfiguration.cookbook_download_path
      @powershell_providers   = nil
      @ohai_retry_delay       = OHAI_RETRY_MIN_DELAY
      @audit                  = AuditStub.instance
      @logger                 = RightLinkLog

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

    # Download cookbooks repositories, update @ok
    # Note: Starting with Chef 0.8, the cookbooks repositories list must be traversed in reverse
    # order to preserve the semantic of the dashboard (first repo has priority)
    #
    # === Return
    # true:: Always return true
    def download_repos
      # Skip download if in dev mode and cookbooks repos directories already have files in them
      return true unless DevState.download_cookbooks?

      @audit.create_new_section('Retrieving cookbooks') unless @cookbook_repos.empty?
      audit_time do
        connection = RightHttpConnection.new(:user_agent => 'Repose client',
                                             :logger => @logger,
                                             :exception => ReposeConnectionException)
        server = find_repose_server(connection)
        @cookbooks.each do |cookbook|
          @audit.update_status("Downloading #{cookbook}")

          request = Net::HTTP::Get.new('/#{cookbook.hash}')
          request['Cookie'] = "repose_ticket=#{cookbook.token}"
          again? = true
          while again?
            begin
              connection.request(:server => server, :port => '80', :protocol => 'https',
                                 :request => request) do |result|
                if result.kind_of?(Net::HTTPSuccess)
                  again? = false
                  tarball = Tempfile.new("tarball")
                  @audit.append_info("Success, now unarchiving")
                  result.read_body do |chunk|
                    tarball << chunk
                  end
                  tarball.close

                  root_dir = File.join(@download_path, cookbook.hash)
                  FileUtils.mkdir_p(root_dir)
                  Dir.chdir(root_dir) do
                    output, status = run('tar', 'xf', tarball.path)
                    if status.exitstatus != 0
                      report_failure("Unknown error: #{status.exitstatus}", output)
                    else
                      @audit.append_info(output)
                    end
                  end
                  tarball.close(true)
                elsif result.kind_of?(HTTPServiceUnavailable)
                  @audit.append_info("Repose server unavailable; retrying", result.body)
                  server = find_repose_server(connection)
                else
                  again? = false
                  report_failure("Unable to download cookbook #{cookbook}", result.to_s)
                end
              end
            rescue ReposeConnectionException => e
              @audit.append_info("Connection interrupted: #{e}; retrying")
              server = find_repose_server(connection)
            end
          end
        end
      end
      true
    end

    # Find a working repose server using the given connection.  Will
    # block until one is found.
    #
    # === Parameters
    # connection(RightHttpConnection):: connection to use
    #
    # === Return
    # address(String):: IP address of working repose server
    def find_repose_server(connection)
      loop do
        possibles = Socket.getaddrinfo(@repose_server, 80, Socket::AF_INET, Socket::SOCK_STREAM,
                                       Socket::IPPROTO_TCP)
        if possibles.empty?
          RightLinkLog.warn("Unable to find any repose servers for #{@repose_server}; retrying")
          sleep 10
          next
        end

        # Try to get to the server health page
        possibles.each do |possible|
          family, port, hostname, address, protocol_family, socket_type, protocol = possible
          request = Net::HTTP::Get.new('/')
          result = connection.request(:server => address, :port => '80', :protocol => 'https',
                                      :request => request)
          return address if result.kind_of?(HTTPSuccess)
        end

        RightLinkLog.warn("All available repose servers for #{@repose_server} are down; retrying")
        sleep 10
      end
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
        # terminiate the providers before the node server as the provider term scripts may still use the node server
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
