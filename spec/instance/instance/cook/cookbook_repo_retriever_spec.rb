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

require 'fileutils'

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'instance', 'cook'))

describe RightScale::CookbookRepoRetriever do
  before(:all) do
    @temp_dir = Dir.mktmpdir('cookbook_repo_retriever_spec')
    @expected_repose_root = File.join(@temp_dir,"repose_root")
    @expected_checkout_root = File.join(@temp_dir, 'checkout_root')
  end

  before(:each) do
    flexmock(RightScale::AgentConfig).should_receive(:dev_cookbook_checkout_dir).and_return(@expected_checkout_root)
  end

  after(:all) do
    FileUtils.rm_rf(@temp_dir) rescue nil  # tidy up
  end

  context :has_cookbooks? do
    it 'when initialized with dev cookbooks, should be true' do
      RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({'sha-1' => RightScale::DevRepository.new})).has_cookbooks?.should be_true
    end

    it 'when initialized with empty dev cookbooks, should be false' do
      RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({})).has_cookbooks?.should be_false
    end

    it 'when initialized with nil dev cookbooks, should be false' do
      RightScale::CookbookRepoRetriever.new(@expected_repose_root, nil).has_cookbooks?.should be_false
    end
  end

  context :should_be_linked? do
    context 'when initialized with dev cookbooks with a cookbook' do
      before(:each) do
        @repo_sha = 'sha-1'
        @position = 'cookbooks/cookbook'
        @repo = RightScale::DevRepository.new
        @repo.positions = [flexmock("cookbook position", :position => @position, :cookbook => nil)]
        @retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({@repo_sha => @repo}))
      end

      it 'repo matches and position matches should be true' do
        @retriever.should_be_linked?(@repo_sha, @position).should be_true
      end

      it 'repo matches and position does not match should be false' do
        @retriever.should_be_linked?(@repo_sha, 'no-match').should be_false
      end

      it 'repo does not match should be false' do
        @retriever.should_be_linked?('sha-2', @position).should be_false
      end
    end

    it 'when initialized with empty dev cookbooks, should be false' do
      retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({}))
      retriever.should_be_linked?(@repo_sha, @position).should be_false
    end

    it 'when initialized with nil dev cookbooks, should be false' do
      retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, nil)
      retriever.should_be_linked?(@repo_sha, @position).should be_false
    end
  end

  context :checkout_cookbook_repos do
    context 'when initialized with dev cookbooks' do
      context 'and scrape succeeds' do
        before(:each) do
          FileUtils.rm_rf(@expected_checkout_root) rescue nil
          FileUtils.rm_rf(@expected_repose_root)  rescue nil

          @repo_sha = 'sha-1'
          @repo_dir = File.join(@expected_checkout_root, @repo_sha)
          @position = 'cookbooks/cookbook'

          mock_scraper = flexmock("Mock RightScraper")
          mock_scraper.should_receive(:scrape).once.and_return do
            FileUtils.mkdir_p(RightScale::CookbookPathMapping.checkout_path(@repo_dir, @position))
            true
          end
          flexmock(RightScraper::Scraper).should_receive(:new).and_return(mock_scraper)

          @repo = RightScale::DevRepository.new
          @repo.url = 'git://fake_git_url'
          @repo.positions = [flexmock("cookbook position", :position => @position, :cookbook => nil)]
          @retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({@repo_sha => @repo}))

          mock_scraper.should_receive(:repo_dir).with(RightScale::CookbookRepoRetriever.to_scraper_hash(@repo)).once.and_return(@repo_dir)
        end

        after(:each) do
          FileUtils.rm_rf(@expected_checkout_root) rescue nil
          FileUtils.rm_rf(@expected_repose_root)  rescue nil
        end

        context 'when a repo has already been checked out' do
          it 'should skip checkout' do
            pending
          end
        end

        it 'should check out repos' do
          @retriever.checkout_cookbook_repos.should be_true
          @retriever.is_checked_out?(@repo_sha).should be_true
        end

        if !::RightScale::Platform.windows? || defined?(::Windows::File::CreateSymbolicLink)
          it 'should be able to link on supported platforms' do
            @retriever.checkout_cookbook_repos.should be_true
            File.exists?(RightScale::CookbookPathMapping.checkout_path(@repo_dir, @position)).should be_true
            @retriever.link(@repo_sha, @position).should be_true
            if ::RightScale::Platform.windows?
              File.exists?(RightScale::CookbookPathMapping.repose_path(@expected_repose_root, @repo_sha, @position)).should be_true
            else
              File.readlink(RightScale::CookbookPathMapping.repose_path(@expected_repose_root, @repo_sha, @position)).should == RightScale::CookbookPathMapping.checkout_path(@repo_dir, @position)
            end
          end
        end

        it 'should NOT be able to link on unsupported platforms' do
          # pretend that this platform doesn't support symlinks
          mock_filesystem = flexmock("fake file system")
          mock_filesystem.should_receive(:create_symlink).and_raise(::RightScale::PlatformNotSupported)
          flexmock(::RightScale::Platform).should_receive(:filesystem).and_return(mock_filesystem)

          @retriever.checkout_cookbook_repos.should be_true
          lambda { @retriever.link(@repo_sha, @position) }.should raise_exception(::RightScale::PlatformNotSupported)
        end
      end

      context 'and scrape fails' do
        before(:each) do
          FileUtils.rm_rf(@expected_checkout_root) rescue nil
          FileUtils.rm_rf(@expected_repose_root)  rescue nil

          @repo_sha = 'sha-1'
          @repo_dir = File.join(@expected_checkout_root, @repo_sha)

          mock_scraper = flexmock("Mock RightScraper")
          mock_scraper.should_receive(:scrape).once.and_return(false)
          flexmock(RightScraper::Scraper).should_receive(:new).and_return(mock_scraper)

          @repo = RightScale::DevRepository.new
          @repo.url = 'git://fake_git_url'
          @repo.positions = [flexmock("cookbook position", :position => @position, :cookbook => nil)]
          @position = 'cookbooks/cookbook'
          @retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({@repo_sha => @repo}))

          mock_scraper.should_receive(:repo_dir).with(RightScale::CookbookRepoRetriever.to_scraper_hash(@repo)).once.and_return(@repo_dir)
        end

        it 'should NOT scrape' do
          #scraping always returns true....
          @retriever.checkout_cookbook_repos.should be_true
        end

        it 'should NOT create links for checked out repos' do
          @retriever.checkout_cookbook_repos.should be_true
          @retriever.is_checked_out?(@repo_sha).should be_false
        end
      end

      context 'and scrape fails for one of multiple dev repos' do
        before(:each) do
          @fail_sha = "sha-2"
          @position = 'cookbooks/cookbook'
          @dev_repos = {}
          [1..3].each do |index|
            repo = RightScale::DevRepository.new
            repo.url = "http://github.com/#{index}"
            repo.positions = [flexmock("cookbook position", :position => "#{@position}#{index}", :cookbook => nil)]
            @dev_repos["sha-#{index}"] = repo
          end
          mock_scraper = flexmock("Mock RightScraper")
          @dev_repos.each_pair do |repo_sha, dev_repo|
            scraper_repo = RightScale::CookbookRepoRetriever.to_scraper_hash(dev_repo)
            mock_scraper.should_receive(:scrape).once.with(scraper_repo).and_return(repo_sha == @fail_sha)
            repo_dir = File.join(@expected_checkout_root, repo_sha)
            mock_scraper.should_receive(:repo_dir).with(RightScale::CookbookRepoRetriever.to_scraper_hash(dev_repo)).once.and_return(repo_dir)
          end
          flexmock(RightScraper::Scraper).should_receive(:new).and_return(mock_scraper)

          @retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new(@dev_repos))
        end

        it 'should NOT scrape' do
          #scraping always returns true....
          @retriever.checkout_cookbook_repos.should be_true
        end

        it 'should NOT create links for checked out repos' do
          @retriever.checkout_cookbook_repos.should be_true
          @dev_repos.keys.each { |repo_sha| @retriever.is_checked_out?(repo_sha).should == (repo_sha == @fail_sha) }
        end
      end
    end

    it 'when initialized with empty dev cookbooks, should not scrape' do
      flexmock(RightScraper::Scraper).new_instances.should_receive(:scrape).never
      flexmock(RightScraper::Scraper).new_instances.should_receive(:repo_dir).never

      retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, RightScale::DevRepositories.new({}))
      retriever.checkout_cookbook_repos { raise "Should not be called" }
    end

    it 'when initialized with nil dev cookbooks, should not scrape' do
      flexmock(RightScraper::Scraper).new_instances.should_receive(:scrape).never
      flexmock(RightScraper::Scraper).new_instances.should_receive(:repo_dir).never

      retriever = RightScale::CookbookRepoRetriever.new(@expected_repose_root, nil)
      retriever.checkout_cookbook_repos { raise "Should not be called" }
    end
  end
end
