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

require 'fileutils'

module RightScale

  # Generate recipes dynamically for RightScripts
  # Usage is:
  #   1. Call 'recipe_from_right_script' for each RightScript that should be converted to a recipe
  #   2. Call 'save' before running Chef, 'recipe_from_right_script' cannot be called after 'save'
  #   3. Use 'repo_dir' to retrieve the Chef cookbook repo path (can be called at any time)
  class RightScriptsCookbook

    # Name of cookbook containing RightScript recipes
    COOKBOOK_NAME = 'right_script_cookbook'

    # Path to generated cookbook repo
    attr_reader :repo_dir

    # Wheter 'save' has been called
    attr_reader :saved

    # Setup temporary directory for cookbook repo containing
    # recipes generated from RightScripts
    #
    # === Parameters
    # audit_id<Fixnum>:: ID of audit entry to be used for RightScripts auditing
    def initialize(audit_id)
      @audit_id     = audit_id
      @saved        = false
      @recipes      = []
      now           = Time.new
      unique_dir    = "right_scripts_#{now.month}_#{now.day}_#{now.hour}_#{now.min}_#{now.sec}"
      @repo_dir     = File.join(InstanceConfiguration::CACHE_PATH, unique_dir)
      @cookbook_dir = File.join(@repo_dir, COOKBOOK_NAME)
      @recipes_dir  = File.join(@cookbook_dir, 'recipes')
      cleanup
      FileUtils.mkdir_p(@recipes_dir)
    end

    # Add RightScript instantiation to cookbook
    #
    # === Parameters
    # script<RightScale::RightScriptInstantiation>:: RightScript to be added
    #
    # === Return
    # recipe<RightScale::RecipeInstantiation>:: Recipe that wraps RightScript
    #
    # === Raise
    # <RightScale::Exceptions::Application>:: If 'save' has been called
    def recipe_from_right_script(script)
      raise RightScale::Exceptions::Application, 'cannot create recipe after cookbook repo has been saved' if @saved
      path = script_path(script.nickname)
      recipe_name = File.basename(path)
      @recipes << recipe_name
      recipe_content = <<-EOS
right_script '#{script.nickname}' do
  parameters(#{script.parameters.inspect})
  cache_dir  '#{cache_dir(script)}'
  audit_id   #{@audit_id}
  source_file '#{path}'
end
      EOS
      File.open(path, 'w') { |f| f.puts script.source }
      File.chmod(0744, path)
      recipe_path = "#{path}.rb"
      File.open(recipe_path, 'w') { |f| f.puts recipe_content }

      recipe = RecipeInstantiation.new("#{COOKBOOK_NAME}::#{recipe_name}", nil, script.id, script.ready)
    end

    # Produce file name for given script nickname
    #
    # === Parameters
    # nickname<String>:: Script nick name
    #
    # === Return
    # path<String>:: Path to corresponding recipe
    def script_path(nickname)
      base_path = nickname.gsub(/[^0-9a-zA-Z_]/,'_')
      base_path = File.join(@recipes_dir, base_path)
      candidate_path = RightLinkConfig[:platform].shell.format_script_file_name(base_path)
      i = 1
      path = candidate_path
      path = candidate_path + (i += 1).to_s while File.exist?(path)
      path
    end

    # Save cookbook repo
    #
    # === Return
    # true:: Always return true
    def save
      unless empty?
        metadata_content = <<-EOS
description "Automatically generated repo, do not modify"
#{@recipes.map { |r| "recipe \"#{COOKBOOK_NAME}::#{r}\", \"RightScript < #{r} >\"" }.join("\n")}
        EOS
        metadata_path = File.join(@cookbook_dir, 'metadata.rb')
        File.open(metadata_path, 'w') { |f| f.puts metadata_content }
      end
      @saved = true
    end

    # Remove cookbooks repository directory
    #
    # === Return
    # true:: Always return true
    def cleanup
      FileUtils.rm_rf(@repo_dir) if File.directory?(@repo_dir)
    end

    # Whether given recipe name corresponds to a converted RightScript
    #
    # === Parameters
    # recipe<String>:: Recipe nickname
    #
    # === Return
    # true:: If recipe was created from converting a RightScript
    # false:: Otherwise
    def right_script?(recipe)
      recipe =~ /^#{COOKBOOK_NAME}::/
    end

    # Human friendly title for given recipe instantiation
    #
    # === Parameters
    # recipe<String>:: Recipe nickname
    #
    # === Return
    # title<String>:: Recipe title to be used in audits
    def self.recipe_title(recipe)
      title = right_script?(recipe) ? 'RightScript' : 'Chef recipe'
      title = "#{title} < #{recipe} >"
    end

    # Path to cache directory for given script
    #
    # === Return
    # path<String>:: Path to directory used for attachments and source
    def cache_dir(script)
      path = File.join(InstanceConfiguration::CACHE_PATH, script.object_id.to_s)
    end

    # Is there no RightScript recipe in repo?
    #
    # === Return
    # true:: If +recipe_from_right_script+ was never called
    # false:: Otherwise
    def empty?
      @recipes.empty?
    end

    # Delete temporary cookbook directory
    def cleanup
      FileUtils.rm_rf(@repo_dir) if File.directory?(@repo_dir)
    end

  end
end