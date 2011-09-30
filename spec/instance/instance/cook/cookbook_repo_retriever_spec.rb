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
  context :has_cookbooks? do
    it 'when initialized with dev cookbooks, should be true' do
      RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new({'sha-1' => {}})).has_cookbooks?.should be_true
    end

    it 'when initialized with empty dev cookbooks, should be false' do
      RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new({})).has_cookbooks?.should be_false
    end

    it 'when initialized with nil dev cookbooks, should be false' do
      RightScale::CookbookRepoRetriever.new(nil, nil, nil).has_cookbooks?.should be_false
    end
  end

  context :should_be_linked? do
    context 'when initialized with dev cookbooks with a cookbook' do
      before(:each) do
        @repo_sha = 'sha-1'
        @position = 'cookbooks/cookbook'
        @retriever = RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new({@repo_sha => {:repo => {}, :positions => [flexmock("cookbook position", :position => @position, :cookbook => nil)]}}))
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
      retriever = RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new({}))
      retriever.should_be_linked?(@repo_sha, @position).should be_false
    end

    it 'when initialized with nil dev cookbooks, should be false' do
      retriever = RightScale::CookbookRepoRetriever.new(nil, nil, nil)
      retriever.should_be_linked?(@repo_sha, @position).should be_false
    end
  end

  context :checkout_cookbook_repos do
    context 'when initialized with dev cookbooks' do
      context 'and scrape succeeds' do
        before(:each) do
          @expected_checkout_root = File.join(Dir.mktmpdir,"my/checkout/path")
          @expected_repose_root = File.join(Dir.mktmpdir,"repose_root")

          FileUtils.rm_rf(@expected_checkout_root) rescue nil
          FileUtils.rm_rf(@expected_repose_root)  rescue nil

          mock_scraper = flexmock("Mock RightScraper")
          mock_scraper.should_receive(:scrape).once.and_return(true)
          mock_scraper.should_receive(:repo_dir).once.and_return(@expected_checkout_root)
          flexmock(RightScraper::Scraper).should_receive(:new).and_return(mock_scraper)

          @repo_sha = 'sha-1'
          @position = 'cookbooks/cookbook'
          @retriever = RightScale::CookbookRepoRetriever.new(@expected_checkout_root, @expected_repose_root, RightScale::DevRepositories.new({@repo_sha => {:repo => {}, :positions => [flexmock("cookbook position", :position => @position, :cookbook => nil)]}}))
        end

        after(:each) do
          FileUtils.rm_rf(@expected_checkout_root) rescue nil
          FileUtils.rm_rf(@expected_repose_root)  rescue nil
        end

        it 'should check out repos' do
          @retriever.checkout_cookbook_repos.should be_true
          @retriever.is_checked_out?(@repo_sha).should be_true
        end

        if !::RightScale::Platform.windows? || defined?(::Windows::File::CreateSymbolicLink)
          it 'should be able to link on supported platforms' do
            # pretend to checkout
            FileUtils.mkdir_p(RightScale::CookbookPathMapping.checkout_path(@expected_checkout_root, @position))

            @retriever.checkout_cookbook_repos.should be_true
            @retriever.link(@repo_sha, @position).should be_true
            if ::RightScale::Platform.windows?
              File.exists?(RightScale::CookbookPathMapping.repose_path(@expected_repose_root, @repo_sha, @position)).should be_true
              File.exists?(RightScale::CookbookPathMapping.checkout_path(@expected_checkout_root, @position)).should be_true
            else
              File.readlink(RightScale::CookbookPathMapping.repose_path(@expected_repose_root, @repo_sha, @position)).should == RightScale::CookbookPathMapping.checkout_path(@expected_checkout_root, @position)
            end
          end
        end

        it 'should NOT be able to link on unsupported platforms' do
          # pretend to thorw
          mock_filesystem = flexmock("fake file system")
          mock_filesystem.should_receive(:create_symlink).and_raise(::RightScale::PlatformNotSupported)
          flexmock(::RightScale::Platform).should_receive(:filesystem).and_return(mock_filesystem)

          # pretend to checkout
          FileUtils.mkdir_p(RightScale::CookbookPathMapping.checkout_path(@expected_checkout_root, @position))

          @retriever.checkout_cookbook_repos.should be_true
          lambda { @retriever.link(@repo_sha, @position) }.should raise_exception(::RightScale::PlatformNotSupported)
        end
      end

      context 'and scrape fails' do
        before(:each) do
          mock_scraper = flexmock("Mock RightScraper")
          mock_scraper.should_receive(:scrape).once.and_return(false)
          mock_scraper.should_receive(:repo_dir).never
          flexmock(RightScraper::Scraper).should_receive(:new).and_return(mock_scraper)

          @repo_sha = 'sha-1'
          @position = 'cookbooks/cookbook'
          @retriever = RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new({@repo_sha => {:repo => {}, :positions => [flexmock("cookbook position", :position => @position, :cookbook => nil)]}}))
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
            repo = {}
            repo[:repo] = {:url=>"http://github.com/#{index}"}
            repo[:positions] = [flexmock("cookbook position", :position => "#{@position}#{index}", :cookbook => nil)]
            @dev_repos["sha-#{index}"] = repo
          end
          mock_scraper = flexmock("Mock RightScraper")
          @dev_repos.each_pair do |repo_sha, dev_repo|
            mock_scraper.should_receive(:scrape).once.with(dev_repo[:repo]).and_return(repo_sha == @fail_sha)
            mock_scraper.should_receive(:repo_dir).times((repo_sha == @fail_sha) ? 1 : 0)
          end
          flexmock(RightScraper::Scraper).should_receive(:new).and_return(mock_scraper)

          @retriever = RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new(@dev_repos))
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

      retriever = RightScale::CookbookRepoRetriever.new(nil, nil, RightScale::DevRepositories.new({}))
      retriever.checkout_cookbook_repos { raise "Should not be called" }
    end

    it 'when initialized with nil dev cookbooks, should not scrape' do
      flexmock(RightScraper::Scraper).new_instances.should_receive(:scrape).never
      flexmock(RightScraper::Scraper).new_instances.should_receive(:repo_dir).never

      retriever = RightScale::CookbookRepoRetriever.new(nil, nil, nil)
      retriever.checkout_cookbook_repos { raise "Should not be called" }
    end
  end
end
