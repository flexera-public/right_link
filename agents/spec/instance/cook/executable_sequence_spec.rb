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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..",
                                   "spec_helper"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..",
                                   "..", "payload_types", "lib",
                                   "payload_types"))
require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..",
                                   "lib", "instance", "cook"))
require 'tmpdir'

module RightScale
  describe ExecutableSequence do
    include SpecHelpers

    SERVER = "a-repose-server"
    before(:all) do
      setup_state
    end

    after(:all) do
      cleanup_state
    end

    before(:each) do
      @auditor = flexmock(AuditStub.instance)
      @auditor.should_receive(:append_info).with(/Starting at/)
      @old_cache_path = InstanceConfiguration::CACHE_PATH
      @temp_cache_path = Dir.mktmpdir
      InstanceConfiguration.const_set(:CACHE_PATH, @temp_cache_path)
    end

    after(:each) do
      InstanceConfiguration.const_set(:CACHE_PATH, @old_cache_path)
      FileUtils.remove_entry_secure(@temp_cache_path)
    end

    it 'should start with an empty bundle' do
      @bundle = ExecutableBundle.new([], [], 2, nil, [], [])
      @sequence = ExecutableSequence.new(@bundle)
    end

    it 'should look up repose servers' do
      flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once
      @bundle = ExecutableBundle.new([], [], 2, nil, [], [SERVER])
      @sequence = ExecutableSequence.new(@bundle)
    end

    context 'with a cookbook specified' do
      before(:each) do
        flexmock(ReposeDownloader).should_receive(:discover_repose_servers).with([SERVER]).once
        @auditor.should_receive(:create_new_section).with("Retrieving cookbooks").once
        @auditor.should_receive(:append_info).with("Requesting nonexistent cookbook").once

        # prevent Chef logging reaching the console during spec test.
        logger = flexmock(RightLinkLog)
        logger.should_receive(:info).with(/Connecting to cookbook server/)
        logger.should_receive(:info).with(/Opening new HTTPS connection to/)

        cookbook = Cookbook.new("4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
                                "nonexistent cookbook")
        position = CookbookPosition.new("foo/bar", cookbook)
        sequence = CookbookSequence.new(['foo'], [position])
        @bundle = ExecutableBundle.new([], [], 2, nil, [sequence],
                                       [SERVER])
      end

      it 'should successfully request a cookbook we can access' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('cookbooks', "4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
               "nonexistent cookbook", ExecutableSequence::CookbookDownloadFailure).once.
          and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield("\000" * 200).once
        @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:append_info).with("").once
        dl.should_receive(:request, Proc).and_yield(response).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_repos)
        @sequence.instance_variable_get(:@ok).should be_nil
      end

      it 'should fail to request a cookbook we can\'t access' do
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).never
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('cookbooks', "4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
               "nonexistent cookbook", ExecutableSequence::CookbookDownloadFailure).once.mock
        dl.should_receive(:request, Proc).and_raise(ExecutableSequence::CookbookDownloadFailure,
                                                    ["cookbooks", "a-sha", "nonexistent cookbook",
                                                     "not found"])
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_repos)
        @sequence.instance_variable_get(:@ok).should be_false
        @sequence.failure_title.should == "Failed to download cookbook"
      end

      it 'should successfully request a cookbook we can access' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('cookbooks', "4cdae6d5f1bc33d8713b341578b942d42ed5817f", "not-a-token",
               "nonexistent cookbook", ExecutableSequence::CookbookDownloadFailure).once.
          and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield("\000" * 200).once
        @auditor.should_receive(:append_info).with("Success; unarchiving cookbook").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:append_info).with("").once
        dl.should_receive(:request, Proc).and_yield(response).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_repos)
        @sequence.instance_variable_get(:@ok).should be_nil
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

      end

      it 'should successfully request an attachment we can access' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('attachments', Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag"),
               "not-a-token", "baz.tar",
               ExecutableSequence::AttachmentDownloadFailure).once.
          and_return(flexmock(ReposeDownloader))
        response = flexmock(Net::HTTPSuccess.new("1.1", "200", "everything good"))
        response.should_receive(:read_body, Proc).and_yield("\000" * 200).once
        dl.should_receive(:request, Proc).and_yield(response).once
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into .*/).once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.instance_variable_get(:@ok).should be_nil
      end

      it 'should fall back to manual download if Repose fails' do
        hash = Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag")
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('attachments', hash, "not-a-token", "baz.tar",
               ExecutableSequence::AttachmentDownloadFailure).once.
          and_return(flexmock(ReposeDownloader))
        dl.should_receive(:request, Proc).
          and_raise(ExecutableSequence::AttachmentDownloadFailure, ["attachments", hash,
                                                                    "baz.tar", "spite"]).once
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
          and_return(true)
        manual_dl.should_receive(:details).with_no_args.and_return("nothing")
        @auditor.should_receive(:update_status).with(/^Downloading baz\.tar into [^ ]* directly$/).once
        @auditor.should_receive(:update_status).with(/^Downloading baz\.tar into [^ ]*$/).once
        @auditor.should_receive(:append_info).with("Repose download failed: spite while downloading #{hash}; falling back to direct download").once
        @auditor.should_receive(:append_info).with("nothing").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.instance_variable_get(:@ok).should be_nil
      end

      it 'should fall back to manual download if no token' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('attachments', Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag"),
               "not-a-token", "baz.tar",
               ExecutableSequence::AttachmentDownloadFailure).never
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
          and_return(true)
        manual_dl.should_receive(:details).with_no_args.and_return("nothing")
        @attachment.token = nil
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into [^ ]* directly/).once
        @auditor.should_receive(:append_info).with("nothing").once
        @auditor.should_receive(:append_info).with(/Duration: \d+\.\d+ seconds/).once
        @auditor.should_receive(:update_status).and_return {|string| p string}
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.instance_variable_get(:@ok).should be_nil
      end

      it 'should fail completely if manual download fails' do
        dl = flexmock(ReposeDownloader).should_receive(:new).
          with('attachments', Digest::SHA1.hexdigest("http://a-url/foo/bar/baz\000an-etag"),
               "not-a-token", "baz.tar",
               ExecutableSequence::AttachmentDownloadFailure).never
        manual_dl = flexmock(Downloader).should_receive(:new).once.and_return(flexmock(Downloader))
        manual_dl.should_receive(:download).with("http://a-url/foo/bar/baz?blah", String).
          and_return(false)
        manual_dl.should_receive(:error).with_no_args.and_return("spite")
        @attachment.token = nil
        @auditor.should_receive(:update_status).with(/Downloading baz\.tar into [^ ]* directly/).once
        @sequence = ExecutableSequence.new(@bundle)
        @sequence.send(:download_attachments)
        @sequence.instance_variable_get(:@ok).should be_false
        @sequence.failure_title.should == "Failed to download attachment 'baz.tar'"
        @sequence.failure_message.should == "spite"
      end
    end
  end
end
