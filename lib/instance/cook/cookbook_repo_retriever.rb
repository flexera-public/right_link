#
# Copyright (c) 2009-2011 RightScale Inc
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
    # Initialize...
    #
    # === Parameters
    # checkout_root (String):: root path to check repos out to
    # repose_root (String):: root of all repose downloaded cookbooks
    # dev_cookbooks (Hash):: collection of repos to be checked out see  RightScale::DevRepositories for hash content
    def initialize(checkout_root, repose_root, dev_cookbooks)
      @checkout_root  = checkout_root
      @repose_root    = repose_root
      @dev_cookbooks  = dev_cookbooks || {}
      @scraper        = RightScraper::Scraper.new(:kind => :cookbook, :basedir => @checkout_root)

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
      @dev_cookbooks[repo_sha][:positions] &&
      @dev_cookbooks[repo_sha][:positions].detect { |dev_position| dev_position.position == position }
    end

    # Was the cookbook checked out?
    #
    # === Parameters
    # repo_sha (String) :: unique identifier of the cookbook repository
    #
    # === Returns
    # true if the given repo is checekd out
    def is_checked_out?(repo_sha)
      !@registered_checkouts[repo_sha].nil?
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
        repo = dev_repo[:repo]
        # checkout the repo
        if @scraper.scrape(repo, &callback)
          # get the root dir the repo was checked out to
          repo_dir = @scraper.repo_dir(repo)
          @registered_checkouts[repo_sha] = repo_dir
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
        repose_path   = CookbookPathMapping.repose_path(@repose_root, repo_sha, position)
        FileUtils.mkdir_p(File.dirname(repose_path))
        Platform.filesystem.create_symlink(checkout_path, repose_path)
        return true
      end
      false
    end
  end
end
