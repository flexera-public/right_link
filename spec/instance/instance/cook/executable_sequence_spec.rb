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
    end

    after(:each) do
      AgentConfig.cache_dir = @old_cache_path
      FileUtils.rm_rf(@temp_cache_path)
    end

    it 'should start with an empty bundle' do
        # mock the cookbook checkout location
      flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)

      @bundle = ExecutableBundle.new([], [], 2, nil, [], [])
      @sequence = ExecutableSequence.new(@bundle)
    end

    it 'should look up repose servers' do
        # mock the cookbook checkout location
      flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once

      @bundle = ExecutableBundle.new([], [], 2, nil, [], [SERVER], DevRepositories.new({}), nil)
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

    context 'with a cookbook specified' do

      it_should_behave_like 'mocks cook'

      before(:each) do
        flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once
        @auditor.should_receive(:create_new_section).with("Retrieving cookbooks").once
        @auditor.should_receive(:append_info).with("Deleting existing cookbooks").once
        @auditor.should_receive(:append_info).with("Requesting nonexistent cookbook").once

        # prevent Chef logging reaching the console during spec test.
        logger = flexmock(Log)
        logger.should_receive(:info).with(/Connecting to cookbook server/)
        logger.should_receive(:info).with(/Opening new HTTPS connection to/)

        cookbook = Cookbook.new("4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                                "nonexistent cookbook")
        position = CookbookPosition.new("foo/bar", cookbook)
        sequence = CookbookSequence.new(['foo'], [position], ["deadbeef"])
        @bundle = ExecutableBundle.new([], [], 2, nil, [sequence], [SERVER], DevRepositories.new({}), nil)

        # mock the cookbook checkout location
        flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      end

      it 'should successfully request a cookbook we can access' do
        tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('cookbooks', "4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                 "nonexistent cookbook", ExecutableSequence::CookbookDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield(tarball).once
        @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:append_info).with("").once
        dl.should_receive(:request, Proc).and_yield(response).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_repos)
        @sequence.should be_okay
      end

      it 'should fail to request a cookbook we can\'t access' do
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).never
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('cookbooks', "4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                 "nonexistent cookbook", ExecutableSequence::CookbookDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        dl.should_receive(:request, Proc).and_raise(ExecutableSequence::CookbookDownloadFailure,
                                                    ["cookbooks", "a-sha", "nonexistent cookbook",
                                                     "not found"])
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_repos)
        @sequence.should have_failed("Failed to download cookbook",
                                     "Cannot continue due to RightScale::ExecutableSequence::CookbookDownloadFailure: not found while downloading a-sha.")
      end

      it 'should successfully request a cookbook we can access' do
        tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('cookbooks', "4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                 "nonexistent cookbook", ExecutableSequence::CookbookDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield(tarball).once
        @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:append_info).with("").once
        dl.should_receive(:request, Proc).and_yield(response).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_repos)
        @sequence.should be_okay
      end
    end

    context 'with an attachment specified' do
      before(:each) do
        flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once
        @auditor = flexmock(AuditStub.instance)
        @auditor.should_receive(:create_new_section).with("Downloading attachments").once
        @attachment = RightScriptAttachment.new("http://a-url/foo/bar/baz?blah", "baz.tar",
                                                "an-etag", "not-a-token")
        instantiation = RightScriptInstantiation.new("a script", "#!/bin/sh\necho foo", {},
                                                     [@attachment], "", 12342, true)
        @bundle = ExecutableBundle.new([instantiation], [], 2, nil, [],
                                       [SERVER])

        # mock the cookbook checkout location
        flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      end

      it 'should successfully request an attachment we can access' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments', Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag"),
                 "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield("\000" * 200).once
        dl.should_receive(:request, Proc).and_yield(response).once
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .*/).once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should be_okay
      end

      it 'should fall back to manual download if Repose fails' do
        hash = Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag")
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments', hash, "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        dl.should_receive(:request, Proc).
            and_raise(ExecutableSequence::AttachmentDownloadFailure, ["attachments", hash,
                                                                      "baz.tar", "spite"]).once
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
            and_return(true)
        manual_dl.should_receive(:details).with_no_args.and_return("nothing")
        @auditor.should_receive(:update_status).with(/^Downloading baz\.tar into .* directly$/).once
        @auditor.should_receive(:update_status).with(/^Downloading baz\.tar into .*$/).once
        @auditor.should_receive(:append_info).with("Repose download failed: spite while downloading #{hash}; falling back to direct download").once
        @auditor.should_receive(:append_info).with("nothing").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should be_okay
      end

      it 'should fall back to manual download if no token' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments', Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag"),
                 "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).never
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
            and_return(true)
        manual_dl.should_receive(:details).with_no_args.and_return("nothing")
        @attachment.token = nil
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .* directly/).once
        @auditor.should_receive(:append_info).with("nothing").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:update_status).and_return { |string| p string }
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should be_okay
      end

      it 'should fail completely if manual download fails' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments', Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag"),
                 "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).never
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
            and_return(false)
        manual_dl.should_receive(:error).with_no_args.and_return("spite")
        @attachment.token = nil
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .* directly/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should have_failed("Failed to download attachment 'baz.tar'", "spite")
      end
    end

    context 'with a RightScale hosted attachment specified' do
      before(:each) do
        flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once
        @auditor = flexmock(AuditStub.instance)
        @auditor.should_receive(:create_new_section).with("Downloading attachments").once
        @attachment = RightScriptAttachment.new("http://a-url/foo/bar/baz?blah", "baz.tar",
                                                "an-etag", "not-a-token", "a-digest")
        instantiation = RightScriptInstantiation.new("a script", "#!/bin/sh\necho foo", {},
                                                     [@attachment], "", 12342, true)
        @bundle = ExecutableBundle.new([instantiation], [], 2, nil, [],
                                       [SERVER])

        # mock the cookbook checkout location
        flexmock(CookState).should_receive(:cookbooks_path).and_return(@temp_cache_path)
      end

      it 'should successfully request an attachment we can access' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments/1', "a-digest", "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield("\000" * 200).once
        dl.should_receive(:request, Proc).and_yield(response).once
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .*/).once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should be_okay
      end

      it 'should fall back to manual download if Repose fails' do
        hash = Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag")
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments/1', "a-digest", "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).once.
            and_return(flexmock(ReposeDownloader))
        dl.should_receive(:request, Proc).
            and_raise(ExecutableSequence::AttachmentDownloadFailure, ["attachments", hash,
                                                                      "baz.tar", "spite"]).once
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
            and_return(true)
        manual_dl.should_receive(:details).with_no_args.and_return("nothing")
        @auditor.should_receive(:update_status).with(/^Downloading baz\.tar into .* directly$/).once
        @auditor.should_receive(:update_status).with(/^Downloading baz\.tar into .*$/).once
        @auditor.should_receive(:append_info).with("Repose download failed: spite while downloading #{hash}; falling back to direct download").once
        @auditor.should_receive(:append_info).with("nothing").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should be_okay
      end

      it 'should fail completely if manual download fails' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
            with('attachments/1', "a-digest", "not-a-token", "baz.tar",
                 ExecutableSequence::AttachmentDownloadFailure,
                 RightScale::Log).never
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
            and_return(false)
        manual_dl.should_receive(:error).with_no_args.and_return("spite")
        @attachment.token = nil
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .* directly/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.should have_failed("Failed to download attachment 'baz.tar'", "spite")
      end
    end

    if !::RightScale::Platform.windows? || defined?(::Windows::File::CreateSymbolicLink)
      context 'dev_cookbooks' do
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
        @bundle = ExecutableBundle.new([], [], 2, nil, cookbooks, [SERVER], dev_cookbooks)

        flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once
        @auditor.should_receive(:append_info).with("Deleting existing cookbooks").once

        tarball = File.open(File.join(File.dirname(__FILE__), "demo_tarball.tar")).binmode.read
        dl = flexmock(ReposeDownloader)
        cookbooks.each do |sequence|
          sequence.positions.each do |position|
            unless dev_cookbooks.repositories[sequence.hash] &&
                dev_cookbooks.repositories[sequence.hash][:positions].detect { |dp| dp.position == position.position }
              dl.should_receive(:new).
                  with('cookbooks', position.cookbook.hash, position.cookbook.token, position.cookbook.name,
                       ExecutableSequence::CookbookDownloadFailure, RightScale::Log).once.
                  and_return(flexmock(ReposeDownloader))
              response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
              response.should_receive(:read_body, Proc).and_yield(tarball).once
              @auditor.should_receive(:append_info).with("Requesting #{position.cookbook.name}").once
              @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
              @auditor.should_receive(:append_info).with("").once
              dl.should_receive(:request, Proc).and_yield(response).once
            end
          end
        end
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once

        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:checkout_repos)
        @sequence.should be_okay
        @sequence.send(:download_repos)
        @sequence.should be_okay
      end

      it_should_behave_like 'mocks cook'

      shared_examples_for 'mocks checkout' do
        before(:each) do
          # counts the scrapes
          @total_scrape_count = 0

          # mock the cookbook checkout location
          @checkout_root_dir = Dir.mktmpdir("executable_sequence_spec")
          flexmock(CookState).should_receive(:cookbooks_path).once.and_return(@checkout_root_dir)

          # mock the scraper so we pretend to checkout cookbooks
          mock_scraper = flexmock("mock scraper for sequence")
          flexmock(::RightScraper::Scraper).
              should_receive(:new).once.with(:kind => :cookbook, :basedir => @checkout_root_dir).
              and_return(mock_scraper)
          @checkout_paths = {}
          @dev_cookbooks.repositories.each_pair do |dev_repo_sha, dev_cookbook|
            repo_base_dir = File.join(@checkout_root_dir, rand(2**32).to_s(32), "repo")
            mock_scraper.should_receive(:scrape).once.with(dev_cookbook[:repo], Proc).and_return do |repo, incremental, callback|
              if @failure_repos[dev_repo_sha]
                false
              else
                @total_scrape_count += 1
                @cookbooks.each do |cookbook_sequence|
                  if cookbook_sequence.hash == dev_repo_sha
                    cookbook_sequence.positions.each do |position|
                      repose_path = File.join(AgentConfig.cookbook_download_dir,
                                              RightScale::ExecutableBundle::DEFAULT_THREAD_NAME,
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
            mock_scraper.should_receive(:repo_dir).once.with(dev_cookbook[:repo]).and_return(repo_base_dir) unless @failure_repos[dev_repo_sha]
          end
          @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
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
          simulate_download_repos(@cookbooks, @dev_cookbooks)
        end

        context 'when all repos checkout successfully' do
          it "should scrape #{@expected_scrape_count} repos" do
            @total_scrape_count.should == @expected_scrape_count
          end

          it 'should symlink repose download path to checkout location only for dev_cookbooks' do
            @cookbooks.each do |cookbook_sequence|
              if @dev_cookbooks.repositories.has_key?(cookbook_sequence.hash)
                dev_cookbook = @dev_cookbooks.repositories[cookbook_sequence.hash]
                failed_positions = @failure_repos[cookbook_sequence.hash].collect { |position| position.position } if @failure_repos.has_key?(cookbook_sequence.hash)
                cookbook_sequence.positions.each do |position|
                  local_basedir = File.join(AgentConfig.cookbook_download_dir,
                                            RightScale::ExecutableBundle::DEFAULT_THREAD_NAME,
                                            cookbook_sequence.hash,
                                            position.position)
                  dev_position = dev_cookbook[:positions].detect { |dp| dp.position == position.position }
                  if failed_positions && failed_positions.include?(position.position)
                    local_basedir.should_not exist_on_filesystem
                  elsif dev_position.nil?
                    # not a dev cookbook, so should not be linked
                    local_basedir.should exist_on_filesystem
                    local_basedir.should_not be_symlink
                  else
                    # is a dev cookbook, so should be linked
                    if Platform.windows?
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
                                            RightScale::ExecutableBundle::DEFAULT_THREAD_NAME,
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

      context 'debugging no cookbooks' do
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

      context 'debugging one cookbook that exists in only one repo' do
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

      context 'debugging one cookbook that exists in two repos' do
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

      context 'debugging multiple cookbooks from multiple repos' do
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

      context "when checkout of one repo fails" do
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
end
