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

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')

require 'rubygems'
require 'chef/log'
require 'fileutils'
require 'right_scraper'

module RightScale

  # Bundle sequence, includes installing dependent packages,
  # downloading attachments and running scripts in given bundle.
  # Also downloads cookbooks and run recipes in given bundle.
  # If an agent identity is given then the executable sequence will attempt
  # to retrieve missing attributes. It will do so indefinitely until the missing
  # attributes are provided by the core agent.
  class ExecutableSequence

    include EM::Deferrable

    # Patch to be applied to inputs after Chef run
    attr_reader :inputs_patch

    # Initialize sequence
    #
    # === Parameter
    # bundle(RightScale::ExecutableBundle):: Bundle to be run
    def initialize(bundle)
      @description            = bundle.to_s
      @auditor                = AuditorProxy.new(bundle.audit_id)
      @right_scripts_cookbook = RightScriptsCookbook.new(@auditor.audit_id)
      @scripts                = bundle.executables.select { |e| e.is_a?(RightScriptInstantiation) }
      recipes                 = bundle.executables.map    { |e| e.is_a?(RecipeInstantiation) ? e : @right_scripts_cookbook.recipe_from_right_script(e) }
      @cookbook_repos         = bundle.cookbook_repositories || []
      @downloader             = Downloader.new
      @scraper                = Scraper.new(InstanceConfiguration.cookbook_download_path)

      # We want to always do full-converge, leave the option in case we change our mind
      persist_run_list = bundle.full_converge
      bundle.full_converge = true

      # Initializes run list for this sequence (partial converge support)
      @run_list = []
      @inputs = {}
      breakpoint = DevState.breakpoint
      recipes.each do |recipe|
        if recipe.nickname == breakpoint
          @auditor.append_info("Breakpoint set, running recipes up to < #{breakpoint} >")
          bundle.full_converge = false
          break
        end
        @run_list << recipe.nickname
        ChefState.deep_merge!(@inputs, recipe.attributes)
      end

      # Retrieve node attributes and deep merge in inputs
      @attributes = ChefState.attributes
      ChefState.deep_merge!(@attributes, @inputs)

      # Setup run list
      if bundle.full_converge
        @run_list = ChefState.merge_run_lists!(ChefState.run_list.dup, @run_list)
      end
      if persist_run_list
        ChefState.merge_run_list(@run_list.select { |r| !@right_scripts_cookbook.right_script?(r) })
      end

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
        converge if @ok
      end
      true
    end

    protected

    # Configure chef so it can find cookbooks and so its logs go to the audits
    #
    # === Return
    # true:: Always return true
    def configure_chef
      # Ohai plugins path and logging
      ohai_plugins = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'chef', 'lib', 'plugins'))
      Ohai::Config[:plugin_path].unshift(ohai_plugins)
      Ohai::Config.log_level RightLinkLog.level

      # Chef logging
      logger = Multiplexer.new(AuditLogger.new(@auditor), RightLinkLog.logger)
      Chef::Log.logger = logger
      Chef::Log.logger.level = RightLinkLog.level_from_sym(RightLinkLog.level)

      # Chef paths and run mode
      if DevState.use_cookbooks_path?
        Chef::Config[:cookbook_path] = DevState.cookbooks_path
        Chef::Log.info("Using development cookbooks repositories path:\n\t- #{Chef::Config[:cookbook_path].join("\n\t- ")}")
      else
        Chef::Config[:cookbook_path] = (@right_scripts_cookbook.empty? ? [] : [ @right_scripts_cookbook.repo_dir ])
      end
      Chef::Config[:solo] = true

      # must set file cache path for Windows case of using remote files, templates. etc.
      platform = RightScale::RightLinkConfig[:platform]
      Chef::Config[:file_cache_path] = File.join(platform.filesystem.cache_dir, 'chef') if platform.windows?
      true
    end

    # Download attachments, update @ok
    #
    # === Return
    # true:: Always return true
    def download_attachments
      unless @scripts.all? { |s| s.attachments.empty? }
        @auditor.create_new_section('Downloading attachments')
        audit_time do
          @scripts.each do |script|
            attach_dir = @right_scripts_cookbook.cache_dir(script)
            script.attachments.each do |a|
              script_file_path = File.join(attach_dir, a.file_name)
              @auditor.update_status("Downloading #{a.file_name} into #{script_file_path}")
              if @downloader.download(a.url, script_file_path)
                @auditor.append_info(@downloader.details)
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
      @auditor.create_new_section("Installing packages: #{packages}")
      success = false
      audit_time do
        success = retry_execution do
          if File.executable? '/usr/bin/yum'
            @auditor.append_output(`yum install -y #{packages} 2>&1`)
          elsif File.executable? '/usr/bin/apt-get'
            ENV['DEBIAN_FRONTEND']="noninteractive"
            @auditor.append_output(`apt-get install -y #{packages} 2>&1`)
          else
            report_failure('Failed to install packages', 'Cannot find yum nor apt-get binary in /usr/bin')
            return true # Not much more we can do here
          end
          $?.success?
        end
      end
      report_failure('Failed to install packages', 'Package install exited with bad status') unless success
      true
    end

    # Download cookbooks repositories, update @ok
    #
    # === Return
    # true:: Always return true
    def download_repos
      # Skip download if in dev mode and cookbooks repos directories already have files in them
      return true unless DevState.download_cookbooks?

      @auditor.create_new_section('Retrieving cookbooks') unless @cookbook_repos.empty?
      audit_time do
        @cookbook_repos.each do |repo|
          next if repo.repo_type == :local
          @auditor.append_info("Downloading #{repo.url}")
          output = []
          result = @scraper.scrape(repo) { |o, _| @auditor.append_output(o) }
          if result
            cookbooks_path = repo.cookbooks_path || []
            if cookbooks_path.empty?
              Chef::Config[:cookbook_path] << @scraper.last_repo_dir
            else
              cookbooks_path.each { |p| Chef::Config[:cookbook_path] << File.join(@scraper.last_repo_dir, p) }
            end
            @auditor.append_output(output.join("\n"))
          else
            report_failure("Failed to download cookbooks #{repo.url}", output.join("\n"))
            return true
          end
        end
      end
      true
    end

    # Chef converge
    #
    # === Return
    # true:: Always return true
    def converge
      @auditor.create_new_section("Converging")
      @auditor.append_info("Run list: < #{@run_list.join(" >, < ")} >")
      attribs = { 'recipes' => @run_list }
      attribs.merge!(@attributes) if @attributes
      c = Chef::Client.new
      begin
        audit_time do
          c.json_attribs = attribs
          c.run_solo
        end
      rescue Exception => e
        report_failure('Chef converge failed', chef_error(e))
        RightLinkLog.debug("Chef failed with '#{e.message}' at\n" + e.backtrace.join("\n"))
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
      if node
        ChefState.merge_attributes(node.attribute)
        patch = ChefState.create_patch(@inputs, ChefState.attributes)
        # We don't want to send back new attributes (ohai etc.)
        patch[:right_only] = {}
        @inputs_patch = patch
      else
        @inputs_patch = ChefState.empty_patch
      end
      @auditor.update_status("completed: #{@description}")
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
      RightLinkLog.error(msg)
      @auditor.update_status("failed: #{ @description }")
      @auditor.append_error(title)
      @auditor.append_error(msg)
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
    # times(Integer):: Number of times block should be retried before giving up
    #
    # === Block
    # Block to be executed
    #
    # === Return
    # success(Boolean):: true if execution was successful, false otherwise.
    def retry_execution(times=InstanceConfiguration::MAX_PACKAGES_INSTALL_RETRIES)
      count = 0
      success = false
      begin
        count += 1
        success = yield
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
      @auditor.append_info("Starting at #{start_time}")
      res = yield
      @auditor.append_info("Duration: #{'%.2f' % (Time.now - start_time)} seconds\n\n")
      res
    end

  end

end
