#
# Copyright (c) 2009-2013 RightScale Inc
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

require 'right_scraper'

module RightScale
  #
  class CookbookRepoRetriever
    attr_reader :checkout_root

    # Maps the given DevRepository to a has that can be consumed by the RightScraper gem
    # TODO: May make sense for  this to a member of the DevRepository class as an instance method.
    #           Also, may want to take a version as a parameter in the future (or not...).
    #
    # === Parameters
    # dev_repo (DevRepository):: core representation of a resource repository
    #
    # === Returns
    # (Hash)::
    #   :repo_type (Symbol):: Type of repository: one of :git, :svn, :download or :local
    #     * :git denotes a 'git' repository that should be retrieved via 'git clone'
    #     * :svn denotes a 'svn' repository that should be retrieved via 'svn checkout'
    #     * :download denotes a tar ball that should be retrieved via HTTP GET (HTTPS if uri starts with https://)
    #     * :local denotes cookbook that is already local and doesn't need to be retrieved
    #   :url (String):: URL to repository (e.g. git://github.com/opscode/chef-repo.git)
    #   :tag (String):: git commit or svn branch that should be used to retrieve repository
    #                       Optional, use 'master' for git and 'trunk' for svn if tag is nil.
    #                       Not used for raw repositories.
    #   :cookbooks_path (Array):: Path to cookbooks inside repostory
    #                                             Optional (use location of repository as cookbook path if nil)
    #   :first_credential (String):: Either the Private SSH key used to retrieve git repositories, or the Username used to retrieve svn and raw repositories
    #   :second_credential (String):: Password used to retrieve svn and raw repositories
    def self.to_scraper_hash(dev_repo)
      repo = {}
      repo[:repo_type]            = dev_repo.repo_type.to_sym unless dev_repo.repo_type.nil?
      repo[:url]                  = dev_repo.url
      repo[:tag]                  = dev_repo.tag
      repo[:resources_path]       = dev_repo.cookbooks_path
      if !dev_repo.ssh_key.nil?
        repo[:first_credential]   = dev_repo.ssh_key
      elsif !(dev_repo.username.nil? && dev_repo.password.nil?)
        repo[:first_credential]   = dev_repo.username
        repo[:second_credential]  = dev_repo.password
      end

      repo
    end

    # Initialize...
    #
    # === Parameters
    # repose_root (String):: root of all repose downloaded cookbooks
    # dev_cookbooks (Hash):: collection of repos to be checked out see  RightScale::DevRepositories for hash content
    def initialize(repose_root, dev_cookbooks)
      @checkout_root  = AgentConfig.dev_cookbook_checkout_dir
      @repose_root    = repose_root
      @dev_cookbooks  = (dev_cookbooks.nil? || dev_cookbooks.repositories.nil?) ? {} : dev_cookbooks.repositories
      @scraper        = RightScraper::Main.new(:kind => :cookbook, :basedir => @checkout_root)
      @registered_checkouts = {}
    end

    # Are there any cookbooks to be checked out?
    #
    # === Returns
    # true if there are cookbooks to be checked out, false otherwise
    def has_cookbooks?
      !@dev_cookbooks.empty?
    end

    # Should there be a link created for this cookbook?
    #
    # === Parameters
    # repo_sha (String) :: unique identifier of the cookbook repository
    # position (String) :: repo relative ppath of the cookbook
    #
    # === Returns
    # true if there is a cookbook in the given repo that should be checekd out
    def should_be_linked?(repo_sha, position)
      @dev_cookbooks.has_key?(repo_sha) &&
      @dev_cookbooks[repo_sha].positions &&
      @dev_cookbooks[repo_sha].positions.detect { |dev_position| dev_position.position == position }
    end

    # Was the cookbook checked out?
    #
    # === Parameters
    # repo_sha (String) :: unique identifier of the cookbook repository
    #
    # === Returns
    # true if the given repo is checekd out
    def is_checked_out?(repo_sha)
      !!repo_dir_for(repo_sha)
    end

    # Checkout directory for given repository hash.
    #
    # === Parameters
    # @param [String] repo_sha for lookup
    #
    # === Return
    # @return [String] checked-out directory or nil
    def repo_dir_for(repo_sha)
      @registered_checkouts[repo_sha]
    end

    # Checkout the given repo and link each dev cookbook to it's matching repose path
    #
    # === Parameters
    # callback (Proc) :: to be called for each repo checked out see RightScraper::Scraper.scrape for details
    #
    # === Return
    #  true
    def checkout_cookbook_repos(&callback)
      @dev_cookbooks.each_pair do |repo_sha, dev_repo|
        repo = self.class.to_scraper_hash(dev_repo)

        # get the root dir this repo should be, or was, checked out to
        repo_dir = @scraper.repo_dir(repo)

        if File.directory?(repo_dir)
          # repo was already checked out on this machine; leave it alone
          # synthesize a scraper callback so our progress listener knows what's up
          if callback
            callback.call(:commit, :initialize, "Skipping checkout -- repository already exists in #{repo_dir}", nil)
          end
          @registered_checkouts[repo_sha] = repo_dir
        else
          # repo wasn't checked out successfully yet; check it out now
          success = false
          begin
            success = @scraper.scrape(repo, &callback)
          ensure
            if success
              @registered_checkouts[repo_sha] = repo_dir
            else
              # nuke the repo dir if checkout fails, so we try again next time
              FileUtils.rm_rf(repo_dir) unless success

              # scraper logger is an odd duck, so just transfer any errors to
              # the normal logger.
              @scraper.errors.each { |e| ::RightScale::Log.error(e) }
              ::RightScale::Log.error("Failed to checkout from #{repo[:url].inspect}")
            end
          end
        end
      end
      true
    end

    # Creates a symlink from the checked out cookbook to the expected repose download location
    #
    # === Parameters
    # repo_sha (String) :: unique identifier of the cookbook repository
    # position (String) :: repo relative ppath of the cookbook
    #
    # === Returns
    # true if link was created, false otherwise
    def link(repo_sha, position)
      # symlink to the checked out cookbook only if it was actually checked out
      if repo_dir = @registered_checkouts[repo_sha]
        checkout_path = CookbookPathMapping.checkout_path(repo_dir, position)
        raise ArgumentError.new("Missing directory cannot be linked: #{checkout_path}") unless File.directory?(checkout_path)
        repose_path   = CookbookPathMapping.repose_path(@repose_root, repo_sha, position)
        FileUtils.mkdir_p(File.dirname(repose_path))
        Platform.filesystem.create_symlink(checkout_path, repose_path)
        return true
      end
      false
    end
  end
end
