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


module RightScale

  # Bundle sequence, includes installing dependent packages,
  # downloading attachments and running scripts in given bundle.
  # Also downloads cookbooks and run recipes in given bundle.
  # If an agent identity is given then the executable sequence will attempt
  # to retrieve missing attributes. It will do so indefinitely until the missing
  # attributes are provided by the core agent.
  class ExecutableSequence

    include EM::Deferrable
  
    # Initialize sequence
    #
    # === Parameter
    # bundle<RightScale::ExecutableBundle>:: Bundle to be run
    # agent_identity<String>:: Agent identity (needed to retrieve missing inputs)
    def initialize(bundle, agent_identity=nil)
      @description          = bundle.to_s
      @auditor              = AuditorProxy.new(bundle.audit_id)
      @scripts              = bundle.executables.select { |e| e.is_a?(RightScriptInstantiation) }
      @original_recipes     = bundle.executables.select { |e| e.is_a?(RecipeInstantiation) }
      @recipes              = bundle.executables.map { |e| e.is_a?(RecipeInstantiation) ? e : script_to_recipe(e) }
      @cookbook_repos       = bundle.cookbook_repositories || []
      @downloader           = Downloader.new
      @prepared_executables = []
      @agent_identity       = agent_identity
    end

    # Run given executable bundle
    # Asynchronous, set deferrable object's disposition
    #
    # === Return
    # true:: Always return true
    def run
      @ok = true
      if @recipes.empty?
        succeed
      else
        configure_chef
        download_attachments if @ok
        install_packages if @ok
        download_cookbooks if @ok
        run_recipe(@recipes.shift) if @ok
      end
      true
    end

    protected

    # Configure chef so it can find cookbooks and so its logs go to the audits
    #
    # === Return
    # true:: Always return true
    def configure_chef
      #Ohai plugins path and logging
      ohai_plugins = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'lib', 'plugins')) 
      Ohai::Config[:plugin_path].unshift(ohai_plugins)
      Ohai::Config.log_level RightLinkLog.level

      #Chef logging
      Chef::Log.logger = AuditLogger.new(@auditor)
      Chef::Log.logger.level = RightLinkLog.level_from_sym(RightLinkLog.level)

      #Chef paths and run mode
      Chef::Config[:cookbook_path] = @cookbook_repos.map { |r| cookbooks_path(r) }.flatten.uniq
      Chef::Config[:cookbook_path] << File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef'))
      Chef::Config[:solo] = true
      true
    end

    # Download attachments, update @ok
    #
    # === Return
    # true:: Always return true
    def download_attachments
      @auditor.create_new_section('Downloading attachments') unless @scripts.all? { |s| s.attachments.empty? }
      audit_time do
        @scripts.each do |script|
          attach_dir = cache_dir(script)
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

    # Download cookbooks, update @ok
    #
    # === Return
    # true:: Always return true
    def download_cookbooks
      @auditor.create_new_section('Retrieving cookbooks') unless @cookbook_repos.empty?
      audit_time do
        @cookbook_repos.each do |repo|
          @auditor.append_info("Downloading #{repo.url}")
          cookbook_dir = cookbook_repo_directory(repo)
          FileUtils.rm_rf(cookbook_dir) if File.exist?(cookbook_dir)
          success, res = false, ''
          case repo.repo_type
          when :download
            success = @downloader.download(repo.url, cookbook_dir, repo.username, repo.password)
            res = success ? @downloader.details : @downloader.error
          when :git
            ssh_cmd = ssh_command(repo)
            res = `#{ssh_cmd} git clone --quiet --depth 1 #{repo.url} #{cookbook_dir} 2>&1`
            success = $? == 0
            if repo.tag && !repo.tag.empty? && repo.tag != 'master' && success
              Dir.chdir(cookbook_dir) do
                res += `#{ssh_cmd} git fetch --depth 1 --tags 2>&1`
                is_tag = `git tag`.split("\n").include?(repo.tag)
                is_branch = `git branch -r`.split("\n").map { |t| t.strip }.include?("origin/#{repo.tag}")
                if is_tag && is_branch
                  res = 'Repository tag ambiguous: could be git tag or git branch'
                  success = false
                elsif is_branch
                  res += `git branch #{repo.tag} origin/#{repo.tag} 2>&1`
                  success = $? == 0
                elsif !is_tag # Not a branch nor a tag, SHA ref? fetch everything so we have all SHAs
                  res += `#{ssh_cmd} git fetch origin master --depth #{2**31 - 1} 2>&1`
                  success = $? == 0
                end
                if success
                  res += `git checkout #{repo.tag} 2>&1`
                  success = $? == 0
                end
              end
            end
          when :svn
            svn_cmd = "svn export #{repo.url} #{cookbook_dir} --non-interactive" +
            (repo.tag && !repo.tag.empty? ? " --revision #{repo.tag}" : '') +
            (repo.username ? " --username #{repo.username}" : '') +
            (repo.password ? " --password #{repo.password}" : '') +
            ' 2>&1'
            res = `#{svn_cmd}`
            success = $? == 0
          when :local
            res = "Using local(test) cookbooks\n"
            success = true
          else
            report_failure('Failed to download cookbooks', "Invalid cookbooks repository type #{repo.repo_type}")
            return true
          end
          if success
            @auditor.append_output(res)
          else
            report_failure("Failed to download cookbooks #{repo.url}", res)
            return true
          end
        end
      end
      true
    end

    # Run next recipe
    #
    # === Parameters
    # recipe<RightScale::RecipeInstantiation>:: Recipe to run
    #
    # === Return
    # true:: Always return true
    def run_recipe(recipe)
      if recipe.ready
        @auditor.create_new_section("Running #{recipe_title(recipe)}")
        attribs = { 'recipes' => [ recipe.nickname ] }
        attribs.merge!(recipe.attributes) if recipe.attributes
        c = Chef::Client.new
        begin
          c.json_attribs = attribs
          c.run_solo
        rescue Exception => e
          report_failure("Failed to run #{recipe_title(recipe)}", chef_error(recipe_title(recipe), e))
          RightLinkLog.debug("Chef failed with '#{e.message}' at\n" + e.backtrace.join("\n"))
        end
        if @ok
          if @recipes.empty?
            succeed
          else
            run_recipe(@recipes.shift)
          end
        end
      elsif @agent_identity
        @auditor.create_new_section("Retrieving missing inputs for #{recipe_title(recipe)}") unless @retried
        @retried = true
        retrieve_missing_attributes(recipe) do
          unless recipe.ready
            @auditor.append_info("#{recipe_title(recipe)} not ready, waiting...")
            sleep(20)
          end
          run_recipe(recipe)
        end
      else
        report_failure("Failed to run #{recipe_title(recipe)}", "#{recipe_title(recipe)} uses environment inputs that are not available (yet?)")
      end
      true
    end

    # Human friendly title for given recipe instantiation
    #
    # === Parameters
    # recipe<RecipeInstantiation>:: Recipe for which to produce title
    #
    # === Return
    # title<String>:: Recipe title to be used in audits
    def recipe_title(recipe)
      title = (recipe.nickname == 'cookbook::right_script' ? 'RightScript' : 'Chef recipe')
      title = "#{title} < #{recipe.nickname} >"
    end

    # Attempt to retrieve missing inputs for given recipe, update recipe attributes and
    # ready fields (set ready field to true if attempt was successful, false otherwise).
    # This is for environment variables that we are waiting on
    # Query for all inputs and cache results
    # Note: This method is asynchronous and takes a continuation block
    #
    # === Parameters
    # recipe<RecipeInstantiation>:: recipe for which to retrieve attributes
    #
    # === Block
    # Continuation block, will be called once attempt to retrieve attributes is completed
    #
    # === Return
    # true:: Always return true
    def retrieve_missing_attributes(recipe)
      scripts_ids = @scripts.select { |s| !s.ready }.map { |s| s.id }
      recipes_ids = @original_recipes.select { |r| !r.ready }.map { |r| r.id }
      Nanite::MapperProxy.instance.request('/booter/get_missing_attributes', { :agent_identity => @agent_identity,
                                                                               :scripts_ids    => scripts_ids,
                                                                               :recipes_ids    => recipes_ids }) do |r|
        res = OperationResult.from_results(r)
        if res.success?
          res.content.each do |e|
            if e.is_a?(RightScriptInstantiation)
              (script = @scripts.detect { |s| s.id == e.id }) && script.ready = true
              ready_recipe = script_to_recipe(e)
            else
              (orig = @original_recipes.detect { |r| r.id == e.id }) && orig.ready = true
              ready_recipe = e
            end
            # We need to test for both the id and nickname to detect the corresponding recipe
            # in our list of recipes to be run because a RightScript and a recipe may both have
            # the same id
            if (recipe.id == ready_recipe.id) && (recipe.nickname == ready_recipe.nickname)
              recipe.attributes = ready_recipe.attributes
              recipe.ready = true
            elsif cur = @recipes.detect { |r| (r.id == ready_recipe.id) && (r.nickname == ready_recipe.nickname) }
              cur.attributes = ready_recipe.attributes
              cur.ready = true
            end
          end
          yield if block_given?
        else
          report_failure("Failed to retrieve missing inputs for #{recipe_title(recipe)}",
            'Could not retrieve inputs' + (res.content.empty? ? '' : ": #{res.content}"))
        end
      end
    end

    # Set status with failure message and audit it
    #
    # === Parameters
    # title<String>:: Title used to update audit status
    # msg<String>:: Failure message
    #
    # === Return
    # true:: Always return true
    def report_failure(title, msg)
      @ok = false
      RightLinkLog.error(msg)
      @auditor.update_status("failed: #{ @description }")
      @auditor.append_error(title)
      @auditor.append_error(msg)
      fail
      true
    end

    # Wrap chef exception with explanatory information and show
    # context of failure
    #
    # === Parameters
    # title<String>:: Title for recipe instantiation that failed
    # e<Exception>:: Exception raised while executing Chef recipe
    #
    # === Return
    # msg<String>:: Human friendly error message
    def chef_error(title, e)
      msg = "An error occurred during the execution of #{title}. The error message was:\n\n"
      msg += e.message
      file, line, meth = e.backtrace[0].scan(/(.*):(\d+):in `(\w+)'/).flatten
      line_number = line.to_i
      if file && line && (line_number.to_s == line)
        if file[0..InstanceConfiguration::COOKBOOK_PATH.size - 1] == InstanceConfiguration::COOKBOOK_PATH
          path = "[COOKBOOKS]/" + file[InstanceConfiguration::COOKBOOK_PATH.size..file.size]
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
    # lines<Array>:: Lines of text
    # index<Integer>:: Index of line that should be formatted for context
    # padding<Integer>:: Number of character to pad line with (includes prefix)
    # prefix<String>:: Single character string used to prefix line
    #                  use line number if not specified
    def context_line(lines, index, padding, prefix=nil)
      return '' if index < 1 || index > lines.size
      margin = prefix ? prefix * index.to_s.size : index.to_s
      "#{margin}#{' ' * ([padding - margin.size, 0].max)} #{lines[index - 1]}"
    end

    # Transform a RightScriptInstantiation into a RecipeInstantiation
    #
    # === Parameters
    # script<RightScale::ScriptInstantiation>:: Script to be wrapped
    #
    # === Return
    # recipe<RightScale::RecipeInstantiation>:: Resulting recipe
    def script_to_recipe(script)
      data = { 'recipes'      => [ 'cookbook::right_script' ],
               'right_script' => { 'nickname'   => script.nickname,
                                   'source'     => script.source,
                                   'parameters' => script.parameters || {},
                                   'cache_dir'  => cache_dir(script),
                                   'audit_id'   => @auditor.audit_id } }
      recipe = RecipeInstantiation.new(script.nickname, data, script.id, script.ready)
    end

    # Path to cache directory for given script
    #
    # === Return
    # path<String>:: Path to directory used for attachments and source
    def cache_dir(script)
      path = File.join(InstanceConfiguration::CACHE_PATH, script.object_id.to_s)
    end
  
    # Directory where cookbooks should be kept
    #
    # === Parameters
    # repo<RightScale::RepositoryInstantiation>:: Repository to retrieve a directory for
    #
    # === Return
    # dir<String>:: Valid path to Unix directory
    def cookbook_repo_directory(repo)
      dir = File.join(InstanceConfiguration::COOKBOOK_PATH, repo.to_s)
    end
    
     # Cookbooks paths where chef will find cookbooks
     #
     # === Parameters
     # repo<RightScale::RepositoryInstantiation>:: Repository to retrieve a directory 
     #
     # === Return
     # paths<Array>:: Array of valid path to Unix directory
     def cookbooks_path(repo)
       dir = cookbook_repo_directory(repo)
       paths, tmp = [], repo.cookbooks_path
       if tmp.nil? || tmp.empty?
         paths << dir
       else
         tmp.each { |p| paths << File.join(dir, p) }
       end
       paths
     end

    # Retry executing given block given number of times
    # Block should return true when it succeeds
    #
    # === Parameters
    # times<Integer>:: Number of times block should be retried before giving up
    #
    # === Block
    # Block to be executed
    #
    # === Return
    # success<Boolean>:: true if execution was successful, false otherwise.
    def retry_execution(times=InstanceConfiguration::MAX_PACKAGES_INSTALL_RETRIES)
      count = 0
      success = false
      begin
        count += 1
        success = yield
      end while !success && count <= times
      success
    end

    # Store public SSH key into ~/.ssh folder and create temporary script that wraps SSH and uses this key
    # If repository does not have need SSH key for access then return empty string
    #
    # === Parameters
    # repo<RightScale::CookbookRepositoryInstantiation>
    #
    # === Return
    # ssh<String>:: Code to initialize GIT_SSH environment variable with path to SSH wrapper script
    # '':: If repository does not require an SSH key
    def ssh_command(repo)
      return '' unless repo.ssh_key
      ssh_keys_dir = File.join(InstanceConfiguration::COOKBOOK_PATH, '.ssh')
      FileUtils.mkdir_p(ssh_keys_dir) unless File.directory?(ssh_keys_dir)
      ssh_key_name = repo.to_s + '.pub'
      ssh_key_path = File.join(ssh_keys_dir, ssh_key_name)
      File.open(ssh_key_path, 'w') { |f| f.puts(repo.ssh_key) }
      File.chmod(0600, ssh_key_path)
      ssh = File.join(InstanceConfiguration::COOKBOOK_PATH, 'ssh')
      File.open(ssh, 'w') { |f| f.puts("ssh -i #{ssh_key_path} -o StrictHostKeyChecking=no $*") }
      File.chmod(0755, ssh)
      ssh = "GIT_SSH=#{ssh}"
    end

    # Audit startup time and duration of given action
    #
    # === Block
    # Block whose execution should be timed
    #
    # === Return
    # res<Object>:: Result returned by given block
    def audit_time
      start_time = Time.now
      @auditor.append_info("Starting at #{start_time}")
      res = yield
      @auditor.append_info("Duration: #{Time.now - start_time} seconds\n\n")
      res
    end

  end

end
