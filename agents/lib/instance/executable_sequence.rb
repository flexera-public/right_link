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
require 'chef/client'
require 'fileutils'

module RightScale

  # Bundle sequence, includes installing dependent packages,
  # downloading attachments and running scripts in given bundle.
  # Also downloads cookbooks and run recipes in given bundle.
  class ExecutableSequence
  
    # Initialize sequence
    #
    # === Parameter
    # bundle<RightScale::ExecutableBundle>:: Bundle to be run
    def initialize(bundle)
      @description          = bundle.to_s
      @auditor              = AuditorProxy.new(bundle.audit_id)
      @scripts              = bundle.executables.select { |e| e.is_a?(RightScriptInstantiation) }
      @recipes              = bundle.executables.map { |e| e.is_a?(RecipeInstantiation) ? e : script_to_recipe(e) }
      @cookbook_repos       = bundle.cookbook_repositories || []
      @downloader           = Downloader.new
      @prepared_executables = []
    end

    # Run given executable bundle
    #
    # === Return
    # @ok<Boolean>:: true if execution was successful, false otherwise    
    def run
      @ok = true
      configure_chef
      download_attachments if @ok
      install_packages if @ok
      download_cookbooks if @ok
      run_recipes if @ok
      @auditor.update_status("completed: #{@description}") if @ok
      @ok
    end

    protected

    # Configure chef so it can find cookbooks and so its logs go to the audits
    #
    # === Return
    # true:: Always return true
    def configure_chef
      Chef::Log.logger = AuditLogger.new(@auditor)
      Chef::Config[:cookbook_path] = @cookbook_repos.map { |r| cookbooks_path(r) }
      Chef::Config[:cookbook_path] << File.dirname(__FILE__)
      Chef::Config[:solo] = true
      true
    end

    # Download attachments, update @ok
    #
    # === Return
    # true:: Always return true
    def download_attachments
      @auditor.create_new_section("Downloading attachments") unless @scripts.all? { |s| s.attachments.empty? }
      audit_time do
        @scripts.each do |script|
          attach_dir = cache_dir(script)
          script.attachments.each do |a|
            script_file_path = File.join(attach_dir, a.file_name)
            @auditor.update_status("Downloading #{a.url} into #{script_file_path}")
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
    #
    # === Return
    # true:: Always return true
    def install_packages
      packages = []
      @scripts.each { |s| packages.push(s.packages) if s.packages && !s.packages.empty? }
      return true if packages.empty?
      packages = packages.uniq.join(" ")
      @auditor.create_new_section("Installing packages: #{packages}")
      audit_time do
        crashcount = 0
        begin
          crashcount += 1
          if File.executable? "/usr/bin/yum"
            @auditor.append_output(`yum install -y #{packages} 2>&1`)
          elsif File.executable? "/usr/bin/apt-get"
            ENV['DEBIAN_FRONTEND'] = "noninteractive" # this prevents promps
            @auditor.append_output(`apt-get update 2>&1`)
            @auditor.append_output(`apt-get install -y #{packages} 2>&1`)
          else
            report_failure("Failed to install packages", "Cannot find yum nor apt-get binary in /usr/bin")
            return true # Not much more we can do here
          end
        end while !$?.success? && crashcount < InstanceConfiguration::MAX_PACKAGES_INSTALL_RETRIES
      end
      report_failure("Failed to install packages", "Package install exited with bad status") unless $?.success?
      true
    end

    # Download cookbooks, update @ok
    #
    # === Return
    # true:: Always return true
    def download_cookbooks
      @auditor.create_new_section("Retrieving cookbooks") unless @cookbook_repos.empty?
      audit_time do
        @cookbook_repos.each do |repo|
          @auditor.append_info("Downloading #{repo.url}")
          cookbook_dir = cookbook_repo_directory(repo)
          FileUtils.rm_rf(cookbook_dir) if File.exist?(cookbook_dir)
          success, res = false, ''
          if repo.protocol == :raw
            success = @downloader.download(repo.url, cookbook_dir, repo.username, repo.password)
            res = success ? @downloader.details : @downloader.error
          else
            case repo.protocol
            when :git
              ssh_cmd = ssh_command(repo)
              res = `#{ssh_cmd} git clone --quiet --depth 1 #{repo.url} #{cookbook_dir} 2>&1`
              success = $? == 0
              if repo.tag && success
                Dir.chdir(cookbook_dir) do
                  res += `#{ssh_cmd} git fetch --tags 2>&1`
                  is_tag = `git tag`.split("\n").include?(repo.tag)
                  is_branch = `git branch -r`.split("\n").map { |t| t.strip }.include?("origin/#{repo.tag}")
                  if is_tag && is_branch
                    res = 'Repository tag ambiguous: could be git tag or git branch'
                    success = false
                  elsif is_branch
                    res += `git branch #{repo.tag} origin/#{repo.tag} 2>&1`
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
              (repo.tag ? " --revision #{repo.tag}" : '') +
              (repo.username ? " --username #{repo.username}" : '') +
              (repo.password ? " --password #{repo.password}" : '') +
              ' 2>&1'
              res = `#{svn_cmd}`
              success = $? == 0
            else
              report_failure("Failed to download cookbooks", "Invalid cookbook repositories protocol #{repo.protocol}")
              return true
            end
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

    # Run recipes in order, update @ok
    #
    # === Return
    # true:: Always return true
    def run_recipes
      run_recipe(@recipes.shift) while @ok && !@recipes.empty?
      true
    end

    # Run one recipe
    #
    # === Parameters
    # recipe<RightScale::RecipeInstantiation>:: Recipe to run
    #
    # === Return
    # true:: Always return true
    def run_recipe(recipe)
      user_attribs = JSON.load(recipe.json) rescue nil if recipe.json && !recipe.json.empty?
      attribs = { 'recipes' => [ recipe.nickname ] }
      attribs.merge!(user_attribs) if user_attribs && user_attribs.is_a?(Hash)
      # The RightScript Chef provider takes care of auditing
      is_rs = attribs['recipes'] == [ 'right_script' ]
      @auditor.create_new_section("Running Chef recipe < #{recipe.nickname} >") unless is_rs
      c = Chef::Client.new
      begin
        c.json_attribs = attribs
        c.run_solo
      rescue Exception => e
        object = is_rs ? "RightScript" : "Chef recipe"
        report_failure("Failed to run #{object} #{recipe.nickname}", e.message)
        RightLinkLog.debug("Chef failed with '#{e.message}' at" + "\n" + e.backtrace.join("\n"))
      end
      true
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
      true
    end

    # Transform a RightScriptInstantiation into a RecipeInstantiation
    #
    # === Parameters
    # script<RightScale::ScriptInstantiation>:: Script to be wrapped
    #
    # === Return
    # recipe<RightScale::RecipeInstantiation>:: Resulting recipe
    def script_to_recipe(script)
      data = { 'recipes'      => [ 'right_script' ],
               'right_script' => { 'nickname'   => script.nickname,
                                   'source'     => script.source,
                                   'parameters' => script.parameters || {},
                                   'cache_dir'  => cache_dir(script),
                                   'audit_id'   => @auditor.audit_id } }
      recipe = RecipeInstantiation.new(script.nickname, data.to_json)
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
    
     # Cookbook path where chef will find cookbooks
     #
     # === Parameters
     # repo<RightScale::RepositoryInstantiation>:: Repository to retrieve a directory 
     #
     # === Return
     # dir<String>:: Valid path to Unix directory
     def cookbooks_path(repo)
       dir = cookbook_repo_directory(repo)
       dir = File.join(dir, repo.cookbooks_path) if repo.cookbooks_path
       dir
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
      Dir.mkdir(ssh_keys_dir) unless File.directory?(ssh_keys_dir)
      ssh_key_name = repo.to_s + '.pub'
      ssh_key_path = File.join(ssh_keys_dir, ssh_key_name)
      File.open(ssh_key_path, 'w') do |f|
        f.puts(repo.ssh_key)
      end
      File.chmod(0600, ssh_key_path)
      ssh = File.join(InstanceConfiguration::COOKBOOK_PATH, 'ssh')
      File.open(ssh, 'w') do |f|
        f.puts("ssh -i #{ssh_key_path} -o StrictHostKeyChecking=no $*")
      end
      File.chmod(755, ssh)
      "GIT_SSH=#{ssh}"
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
