#--
# Copyright: Copyright (c) 2010 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))
require 'tmpdir'
require 'right_agent/core_payload_types'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'instance', 'cook'))
require 'right_scraper'

module RightScale
  describe ExecutableSequence do

    include SpecHelper

    @@default_cache_path = nil

    SERVER = "a-repose-server"
    before(:all) do
      setup_state
    end

    after(:all) do
      cleanup_state
      FileUtils.rm_rf(@@default_cache_path) if @@default_cache_path
    end

    before(:each) do
      @auditor = flexmock(AuditStub.instance)
      @auditor.should_receive(:append_info).with(/Starting at/)
      @old_cache_path = AgentConfig.cache_dir
      @temp_cache_path = Dir.mktmpdir
      @@default_cache_path ||= @temp_cache_path
      AgentConfig.cache_dir = @temp_cache_path

      # FIX: currently these tests do not need EM, so we mock next_tick so we do not pollute EM.
      # Should we run the entire sequence in em for these tests?
      flexmock(EM).should_receive(:next_tick)

      # For ReposeDownloader
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with(SERVER, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "hostname", "1.2.3.4", 2, 1, 6], ["AF_INET", 443, "hostname", "5.6.7.8", 2, 1, 6]])
    end

    after(:each) do
      AgentConfig.cache_dir = @old_cache_path
      FileUtils.rm_rf(@temp_cache_path)
    end
    
    context :initialize do
      it 'should set a default thread name if none or nil received' do
        bundle = RightScale::PayloadFactory.make_bundle()
        executable_sequence = ExecutableSequence.new(bundle)
        
        executable_sequence.instance_variable_get(:@thread_name).should_not be_nil
      end
      
      it 'should Log if it receives a bundle with a nil thread name' do
        bundle = RightScale::PayloadFactory.make_bundle()
        flexmock(Log).should_receive(:warn).once.by_default
        
        ExecutableSequence.new(bundle)
      end
    end

    it 'should start with an empty bundle' do
        # mock the cookbook checkout location
      flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)

      @bundle = RightScale::PayloadFactory.make_bundle(:audit_id              => 2,
                                                       :cookbooks             => [],
                                                       :repose_servers        => [SERVER])
      @sequence = ExecutableSequence.new(@bundle)
    end

    it 'should instantiate a ReposeDownloader' do
        # mock the cookbook checkout location
      flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      mock_repose_downloader = flexmock('Repose Downloader')
      mock_repose_downloader.should_receive(:logger=).once.and_return(@logger)
      flexmock(ReposeDownloader).should_receive(:new).with([SERVER]).once.and_return(mock_repose_downloader)

      @bundle = RightScale::PayloadFactory.make_bundle(:audit_id              => 2,
                                                       :cookbooks             => [],
                                                       :repose_servers        => [SERVER],
                                                       :dev_cookbooks         => DevRepositories.new({}))
      @sequence = ExecutableSequence.new(@bundle)
    end

    Spec::Matchers.define :be_okay do
      match do |sequence|
        sequence.instance_variable_get(:@ok) != false
      end
      failure_message_for_should do |sequence|
        "should have been okay, but saw this error:\n#{sequence.failure_title}\n#{sequence.failure_message}"
      end
      failure_message_for_should_not do |sequence|
        "should not have been okay, but was"
      end
      description do
        "should be in an okay state"
      end
    end

    Spec::Matchers.define :have_failed do |title, message|
      match do |sequence|
        sequence.instance_variable_get(:@ok) == false &&
            sequence.failure_title == title &&
            sequence.failure_message == message
      end
      failure_message_for_should do |sequence|
        if sequence.instance_variable_get(:@ok) != false
          "should have failed, but succeeded"
        else
          "should have failed with this error:\n#{title}\n#{message}\nbut saw this error:\n#{sequence.failure_title}\n#{sequence.failure_message}"
        end
      end
      failure_message_for_should_not do |sequence|
        "should have not failed with this error:\n#{title}\n#{message}\nbut saw this error:\n#{sequence.failure_title}\n#{sequence.failure_message}"
      end
      description do
        "should be not be an okay state"
      end
    end

    context 'given the bundle contains cookbooks' do

      it_should_behave_like 'mocks cook'

      before(:each) do
        @auditor.should_receive(:create_new_section).with("Retrieving cookbooks").once
        @auditor.should_receive(:append_info).with(/Downloading cookbook 'nonexistent cookbook' \([0-9a-f]+\)/).once

        # prevent Chef logging reaching the console during spec test.
        @logger = flexmock(Log)
        @logger.should_receive(:info).with("Deleting existing cookbooks").once
        @logger.should_receive(:info).with(/Connecting to cookbook server/)
        @logger.should_receive(:info).with(/Opening new HTTPS connection to/)

        cookbook = Cookbook.new("4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                                "nonexistent cookbook")
        position = CookbookPosition.new("foo/bar", cookbook)
        sequence = CookbookSequence.new(['foo'], [position], ["deadbeef"])

        @bundle = RightScale::PayloadFactory.make_bundle(:audit_id        => 2,
                                                         :cookbooks       => [sequence],
                                                         :repose_servers  => [SERVER],
                                                         :dev_cookbooks   => DevRepositories.new({}))

        # mock the cookbook checkout location
        flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      end

      it 'should download accessible cookbooks' do
        tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
        mock_repose_downloader = flexmock('ReposeDownloader')
        mock_repose_downloader.should_receive(:logger=).once.and_return(@logger)
        flexmock(ReposeDownloader).should_receive(:new).with([SERVER]).once.and_return(mock_repose_downloader)
        @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:append_info).with(/Downloaded \'.*\' .* at .*/).once
        @auditor.should_receive(:append_info).with("").once
        mock_repose_downloader.should_receive(:download).with('/cookbooks/4cdae6d5f1bc33d8713b341578b942d42ed5817f', Proc).and_yield(tarball).once
        mock_repose_downloader.should_receive(:details).and_return("Downloaded '4cdae6d5f1bc33d8713b341578b942d42ed5817f' (40K) at 5K/s").once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_cookbooks)
        @sequence.should be_okay
      end

      it 'should not download inaccessible cookbooks' do
        @logger.should_receive(:info).never
        mock_repose_downloader = flexmock('ReposeDownloader')
        mock_repose_downloader.should_receive(:logger=).once.and_return(@logger)
        flexmock(ReposeDownloader).should_receive(:new).with([SERVER]).once.and_return(mock_repose_downloader)
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).never
        mock_repose_downloader.should_receive(:download).with('/cookbooks/4cdae6d5f1bc33d8713b341578b942d42ed5817f', Proc).and_raise(ReposeDownloader::DownloadException)
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_cookbooks)
        @sequence.should have_failed("Failed to download cookbook",
                                     "Cannot continue due to RightScale::ReposeDownloader::DownloadException: RightScale::ReposeDownloader::DownloadException.")
      end
    end

    context 'with a RightScale hosted attachment specified' do
      before(:each) do
        @auditor = flexmock(AuditStub.instance)
        @auditor.should_receive(:create_new_section).with("Downloading attachments").once
        @attachment = RightScriptAttachment.new("http://a-url/foo/bar/baz?blah", "baz.tar",
                                                "an-etag", "not-a-token", "a-digest")
        instantiation = RightScriptInstantiation.new("a script", "#!/bin/sh\necho foo", {},
                                                     [@attachment], "", 12342, true)

        @bundle = RightScale::PayloadFactory.make_bundle(:executables     => [instantiation],
                                                         :audit_id        => 2,
                                                         :cookbooks       => [],
                                                         :repose_servers  => [SERVER])

        # mock the cookbook checkout location
        flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      end

      it 'should successfully request an attachment we can access' do
        tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
        mock_repose_downloader = flexmock('ReposeDownloader')
        mock_repose_downloader.should_receive(:logger=).once.and_return(@logger)
        flexmock(ReposeDownloader).should_receive(:new).with([SERVER]).once.and_return(mock_repose_downloader)
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .*/).once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:append_info).with(/Downloaded \'.*\' .* at .*/).once
        mock_repose_downloader.should_receive(:download).with('http://a-url/foo/bar/baz?blah', Proc).and_yield(tarball).once
        mock_repose_downloader.should_receive(:details).and_return("Downloaded '4cdae6d5f1bc33d8713b341578b942d42ed5817f' (40K) at 5K/s").once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should be_okay
      end

      it 'should fail completely if download fails' do
        mock_repose_downloader = flexmock('ReposeDownloader')
        mock_repose_downloader.should_receive(:logger=).once.and_return(@logger)
        flexmock(ReposeDownloader).should_receive(:new).with([SERVER]).once.and_return(mock_repose_downloader)
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .*/).once
        @auditor.should_receive(:append_info).with("Repose download failed: SocketError.")
        mock_repose_downloader.should_receive(:download).with('http://a-url/foo/bar/baz?blah', Proc).and_raise(SocketError.new).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should have_failed("Failed to download attachment 'baz.tar'", "SocketError")
      end
    end

    context 'cookbook development' do
      Spec::Matchers.define :be_symlink_to do |path|
        match do |link|
          File.readlink(link) == path
        end
        failure_message_for_should do |link|
          "expected #{link} to link to #{path}, but does not"
        end
        failure_message_for_should_not do |link|
          "expected #{link} NOT to link to #{path}, but it does"
        end
        description do
          "should be symlink to #{path}"
        end
      end

      Spec::Matchers.define :be_symlink do
        match do |path|
          File.symlink?(path)
        end
        failure_message_for_should do |path|
          "expected #{path} to be a link, but is not"
        end
        failure_message_for_should_not do |sequence|
          "expected #{path} NOT to be a link, but it is"
        end
        description do
          "should be symlink"
        end
      end

      Spec::Matchers.define :exist_on_filesystem do
        match do |path|
          File.exists?(path)
        end
        failure_message_for_should do |path|
          "expected #{path} to exist, but does not"
        end
        failure_message_for_should_not do |path|
          "expected #{path} NOT to exist, but it does"
        end
        description do
          "should be a file or directory"
        end
      end

      def build_cookbook_sequences
        cookbook1r1 = Cookbook.new("1cdae6d5f1bc33d8713b341578b942d42ed5817f", "token1", "test_cookbook1")
        cookbook1r2 = Cookbook.new("3cdae6d5f1bc33d8713b341578b942d42ed5817f", "token2", "test_cookbook1")
        cookbook2r1 = Cookbook.new("5cdae6d5f1bc33d8713b341578b942d42ed5817f", "token3", "test_cookbook2")
        cookbook3r3 = Cookbook.new("7cdae6d5f1bc33d8713b341578b942d42ed5817f", "token4", "test_cookbook3")

        cookbook1r1_position = CookbookPosition.new("cookbooks/test_cookbook1", cookbook1r1)
        cookbook1r2_position = CookbookPosition.new("other_cookbooks/test_cookbook1", cookbook1r2)
        cookbook2r1_position = CookbookPosition.new("other_cookbooks/test_cookbook2", cookbook2r1)
        cookbook3r3_position = CookbookPosition.new("test_cookbook3", cookbook3r3)

        cookbook_sequence_r1 = CookbookSequence.new(['cookbooks', 'other_cookbooks'],
                                                    [cookbook1r1_position, cookbook2r1_position],
                                                    "e59ff97941044f85df5297e1c302d260")
        cookbook_sequence_r2 = CookbookSequence.new(['other_cookbooks'],
                                                    [cookbook1r2_position],
                                                    "53961c3d705734f5e1f473c0d706330d")
        cookbook_sequence_r3 = CookbookSequence.new(['cookbooks'],
                                                    [cookbook3r3_position],
                                                    "b14e6313910d695e68abbd354b10a8fa")

        {:cookbooks => [cookbook_sequence_r1, cookbook_sequence_r2, cookbook_sequence_r3],
         :sequences_by_cookbook_name => {"test_cookbook1" => [cookbook_sequence_r1, cookbook_sequence_r2],
                                         "test_cookbook2" => [cookbook_sequence_r1],
                                         "test_cookbook3" => [cookbook_sequence_r3]}}
      end

      def build_dev_sequences(sequences_by_cookbook_name, cookbook_names)
        # FIX: simulating uniq because CookbookSequence defines hash which defeats Array.uniq as it depends on hash to determine uniq....
        cookbook_sequences = cookbook_names.inject({}) { |memo, name| sequences_by_cookbook_name[name].
            each { |sequence| memo[sequence.hash] = sequence }; memo }.values
        dev_repo = RightScale::DevRepositories.new
        cookbook_sequences.each do |cookbook_sequence|
          positions = cookbook_sequence.positions.select { |position| cookbook_names.include?(position.cookbook.name) }
          dev_repo.add_repo(cookbook_sequence.hash, {:repo_type => :git,
                                                     :url => "http://github.com/#{cookbook_sequence.hash}"}, positions)
        end
        dev_repo
      end

      def simulate_download_repos(cookbooks, dev_cookbooks)
        @bundle = RightScale::PayloadFactory.make_bundle(:audit_id        => 2,
                                                         :cookbooks       => cookbooks,
                                                         :repose_servers  => [SERVER],
                                                         :dev_cookbooks   => dev_cookbooks)

        flexmock(Log).should_receive(:info).with("Deleting existing cookbooks").once

        unless dev_cookbooks.nil? || dev_cookbooks.empty?
          @auditor.should_receive(:create_new_section).with("Checking out cookbooks for development").once
          @auditor.should_receive(:append_info).with("Cookbook repositories will be checked out to #{RightScale::AgentConfig.dev_cookbook_checkout_dir}").once
        end

        tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
        dl = flexmock(ReposeDownloader)

        unless cookbooks.nil? || cookbooks.empty?
          @auditor.should_receive(:create_new_section).with("Retrieving cookbooks").once
        end

        cookbooks.each do |sequence|
          sequence.positions.each do |position|
            unless dev_cookbooks.repositories[sequence.hash] &&
                dev_cookbooks.repositories[sequence.hash].positions.detect { |dp| dp.position == position.position }
              tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
              mock_repose_downloader = flexmock('ReposeDownloader')
              mock_repose_downloader.should_receive(:logger=).and_return(@logger)
              flexmock(ReposeDownloader).should_receive(:new).with([SERVER]).and_return(mock_repose_downloader)
              @auditor.should_receive(:append_info).with(/Downloading cookbook \'.*\' \(.*\)/)
              @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
              @auditor.should_receive(:append_info).with(/Downloaded \'.*\' .* at .*/).once
              @auditor.should_receive(:append_info).with("").once
              mock_repose_downloader.should_receive(:download).and_yield(tarball)
              mock_repose_downloader.should_receive(:details).and_return("Downloaded '4cdae6d5f1bc33d8713b341578b942d42ed5817f' (40K) at 5K/s")
            end
          end
        end
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once

        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:checkout_cookbook_repos)
        @sequence.should be_okay
        @sequence.send(:download_cookbooks)
        @sequence.should be_okay
      end

      it_should_behave_like 'mocks cook'

      shared_examples_for 'mocks checkout' do
        before(:each) do
          #dev cookbooks do not work on Windows ... for now.....
          pending unless !::RightSupport::Platform.windows? || defined?(::Windows::File::CreateSymbolicLink)

          # counts the scrapes
          @total_scrape_count = 0

          # mock the cookbook checkout location
          @checkout_root_dir = Dir.mktmpdir("executable_sequence_spec")

          # mock the scraper so we pretend to checkout cookbooks
          mock_scraper = flexmock("mock scraper for sequence")
          flexmock(::RightScraper::Scraper).
              should_receive(:new).once.with(:kind => :cookbook, :basedir => RightScale::AgentConfig.dev_cookbook_checkout_dir).
              and_return(mock_scraper)
          @checkout_paths = {}
          @dev_cookbooks.repositories.each_pair do |dev_repo_sha, dev_cookbook|
            repo_base_dir = File.join(@checkout_root_dir, rand(2**32).to_s(32), "repo")
            mock_scraper.should_receive(:scrape).once.with(RightScale::CookbookRepoRetriever.to_scraper_hash(dev_cookbook), Proc).and_return do |repo, incremental, callback|
              if @failure_repos[dev_repo_sha]
                false
              else
                @total_scrape_count += 1
                @cookbooks.each do |cookbook_sequence|
                  if cookbook_sequence.hash == dev_repo_sha
                    cookbook_sequence.positions.each do |position|
                      repose_path = File.join(AgentConfig.cookbook_download_dir,
                                              RightScale::AgentConfig.default_thread_name,
                                              cookbook_sequence.hash,
                                              position.position)
                      checkout_path = File.join(repo_base_dir, position.position)
                      @checkout_paths[repose_path] = checkout_path
                      FileUtils.mkdir_p(checkout_path)
                    end
                  end
                end
                true
              end
            end
            mock_scraper.should_receive(:repo_dir).once.with(RightScale::CookbookRepoRetriever.to_scraper_hash(dev_cookbook)).and_return(repo_base_dir)
          end

          unless @dev_cookbooks.repositories.nil? || @dev_cookbooks.repositories.empty?
            @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
          end
        end

        after(:each) do
          @checkout_paths.each_pair do |repose_path, checkout_path|
            FileUtils.rm_rf(repose_path)
            FileUtils.rm_rf(checkout_path)
          end
          FileUtils.rm_rf(@checkout_root_dir)
        end
      end

      shared_examples_for 'checks out dev repos' do
        before(:each) do
          #dev cookbooks do not work on Windows ... for now.....
          pending unless !::RightSupport::Platform.windows? || defined?(::Windows::File::CreateSymbolicLink)

          simulate_download_repos(@cookbooks, @dev_cookbooks)
        end

        context 'when some repos checkout successfully' do
          it "should scrape the expected number of repos" do
            @total_scrape_count.should == @expected_scrape_count
          end

          it 'should symlink repose download path to checkout location only for dev_cookbooks' do
            @cookbooks.each do |cookbook_sequence|
              if @dev_cookbooks.repositories.has_key?(cookbook_sequence.hash)
                dev_cookbook = @dev_cookbooks.repositories[cookbook_sequence.hash]
                failed_positions = @failure_repos[cookbook_sequence.hash].collect { |position| position.position } if @failure_repos.has_key?(cookbook_sequence.hash)
                cookbook_sequence.positions.each do |position|
                  local_basedir = File.join(AgentConfig.cookbook_download_dir,
                                            RightScale::AgentConfig.default_thread_name,
                                            cookbook_sequence.hash,
                                            position.position)
                  dev_position = dev_cookbook.positions.detect { |dp| dp.position == position.position }
                  if failed_positions && failed_positions.include?(position.position)
                    local_basedir.should_not exist_on_filesystem
                  elsif dev_position.nil?
                    # not a dev cookbook, so should not be linked
                    local_basedir.should exist_on_filesystem
                    local_basedir.should_not be_symlink
                  else
                    # is a dev cookbook, so should be linked
                    if RightSupport::Platform.windows?
                      File.exists?(local_basedir).should be_true
                    else
                      local_basedir.should be_symlink_to(@checkout_paths[local_basedir])
                    end
                  end
                end
              else
                # no cookbook should be symlink
                cookbook_sequence.positions.each do |position|
                  local_basedir = File.join(AgentConfig.cookbook_download_dir,
                                            RightScale::AgentConfig.default_thread_name,
                                            cookbook_sequence.hash,
                                            position.position)
                  local_basedir.should exist_on_filesystem
                  local_basedir.should_not be_symlink
                end
              end
            end
          end
        end
      end

      context 'given no dev cookbooks' do
        before(:each) do
          sequences = build_cookbook_sequences
          @cookbooks = sequences[:cookbooks]
          @sequences_by_cookbook_name = sequences[:sequences_by_cookbook_name]
          @dev_cookbooks = DevRepositories.new
          @expected_scrape_count = 0
          @failure_repos = {}
        end
        it_should_behave_like 'mocks checkout'
        it_should_behave_like 'checks out dev repos'
      end

      context 'given one dev cookbook that exists in only one repo' do
        context 'repo contains only one cookbook' do
          before(:each) do
            sequences = build_cookbook_sequences
            @cookbooks = sequences[:cookbooks]
            @sequences_by_cookbook_name = sequences[:sequences_by_cookbook_name]
            @dev_cookbooks = build_dev_sequences(@sequences_by_cookbook_name, ["test_cookbook3"])
            @expected_scrape_count = 1
            @failure_repos = {}
          end
          it_should_behave_like 'mocks checkout'
          it_should_behave_like 'checks out dev repos'
        end

        context 'repo contains more than one cookbook' do
          before(:each) do
            sequences = build_cookbook_sequences
            @cookbooks = sequences[:cookbooks]
            @sequences_by_cookbook_name = sequences[:sequences_by_cookbook_name]
            @dev_cookbooks = build_dev_sequences(@sequences_by_cookbook_name, ["test_cookbook2"])
            @expected_scrape_count = 1
            @failure_repos = {}
          end

          it_should_behave_like 'mocks checkout'
          it_should_behave_like 'checks out dev repos'
        end
      end

      context 'given one dev cookbook that exists in two repos' do
        before(:each) do
          sequences = build_cookbook_sequences
          @cookbooks = sequences[:cookbooks]
          @sequences_by_cookbook_name = sequences[:sequences_by_cookbook_name]
          @dev_cookbooks = build_dev_sequences(@sequences_by_cookbook_name, ["test_cookbook1"])
          @expected_scrape_count = 2
          @failure_repos = {}
        end
        it_should_behave_like 'mocks checkout'
        it_should_behave_like 'checks out dev repos'
      end

      context 'given multiple dev cookbooks from multiple repos' do
        before(:each) do
          sequences = build_cookbook_sequences
          @cookbooks = sequences[:cookbooks]
          @sequences_by_cookbook_name = sequences[:sequences_by_cookbook_name]
          @dev_cookbooks = build_dev_sequences(@sequences_by_cookbook_name, ["test_cookbook1",
                                                                             "test_cookbook2",
                                                                             "test_cookbook3"])
          @expected_scrape_count = 3
          @failure_repos = {}
        end
        it_should_behave_like 'mocks checkout'
        it_should_behave_like 'checks out dev repos'
      end

      context 'given a repo that is not available for checkout' do
        before(:each) do
          sequences = build_cookbook_sequences
          @cookbooks = sequences[:cookbooks]
          @sequences_by_cookbook_name = sequences[:sequences_by_cookbook_name]
          @dev_cookbooks = build_dev_sequences(@sequences_by_cookbook_name, ["test_cookbook1",
                                                                             "test_cookbook2",
                                                                             "test_cookbook3"])
          @expected_scrape_count = 2

          @failure_repos = {}
          @sequences_by_cookbook_name["test_cookbook2"].each { |sequence| @failure_repos[sequence.hash] = sequence.positions }
        end

        it_should_behave_like 'mocks checkout'
        it_should_behave_like 'checks out dev repos'
      end
    end
  end
end
