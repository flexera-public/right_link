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

require File.join(File.dirname(__FILE__), 'spec_helper')
require 'right_scraper'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'plugins'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'right_providers'))

module RightScale
  class ExecutableSequence
    # monkey-patch delays for faster testing

    OHAI_RETRY_MIN_DELAY = 0.1
    OHAI_RETRY_MAX_DELAY = 1
  end
end

describe RightScale::ExecutableSequence do

  include RightScale::SpecHelper

  context 'Testing sequence execution' do

    it_should_behave_like 'mocks cook'
    it_should_behave_like 'mocks shutdown request proxy'
    it_should_behave_like 'mocks metadata'

    before(:all) do
      flexmock(RightScale::Log).should_receive(:debug)
      @attachment_file = File.normalize_path(File.join(File.dirname(__FILE__), '__test_download__'))
      File.open(@attachment_file, 'w') { |f| f.write('Some attachment content') }
      platform = RightScale::Platform
      @cache_dir = File.normalize_path(File.join(platform.filesystem.temp_dir, 'executable_sequence_spec'))
      Chef::Resource::RightScript.const_set(:DEFAULT_CACHE_DIR_ROOT, @cache_dir)
    end

    before(:each) do
      setup_state
      setup_script_execution
      @script = flexmock(:nickname => '__TestScript', :parameters => {}, :ready => true)
      @script.should_receive(:is_a?).with(RightScale::RightScriptInstantiation).and_return(true)
      @script.should_receive(:is_a?).with(RightScale::RecipeInstantiation).and_return(false)

      @bundle = RightScale::PayloadFactory.make_bundle(:executables => [ @script ],
                                                       :audit_id => 0,
                                                       :full_converge => true,
                                                       :cookbooks => [],
                                                       :repose_servers => ["hostname"],
                                                       :dev_cookbooks => RightScale::DevRepositories.new)

      @thread_name = RightScale::AgentConfig.default_thread_name

      @auditor = flexmock(RightScale::AuditStub.instance)
      @auditor.should_receive(:create_new_section)
      @auditor.should_receive(:append_info)
      @auditor.should_receive(:append_output)
      @auditor.should_receive(:update_status)

      # prevent Chef logging reaching the console during spec test.
      logger = flexmock(RightScale::Log.logger)
      logger.should_receive(:info).and_return(true)
      logger.should_receive(:error).and_return(true)

      # Mock out Actual Repose downloader
      mock_repose_downloader = flexmock('Repose Downloader')
      mock_repose_downloader.should_receive(:logger=).once.and_return(logger)
      mock_repose_downloader.should_receive(:download).and_return("OK")
      mock_repose_downloader.should_receive(:details).and_return("details")
      flexmock(RightScale::ReposeDownloader).should_receive(:new).and_return(mock_repose_downloader)
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with("hostname", 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "hostname", "1.2.3.4", 2, 1, 6], ["AF_INET", 443, "hostname", "5.6.7.8", 2, 1, 6]])

      # reset chef cookbooks path
      Chef::Config[:cookbook_path] = []
    end

    after(:all) do
      cleanup_state
      cleanup_script_execution
      FileUtils.rm(@attachment_file) if @attachment_file
      FileUtils.rm_rf(@cache_dir) if @cache_dir
    end

    # Run sequence and print out exceptions
    def run_sequence
      res = nil
      run_em_test(:timeout => 60) do
        @sequence.callback { res = true;  stop_em_test }
        @sequence.errback  { res = false; stop_em_test }
        @sequence.run
      end
      res
    end

    def format_script_text(exit_code)
      platform = RightScale::Platform
      return platform.windows? ?
             "exit #{exit_code}" :
             "#!/bin/sh\nruby -e 'exit(#{exit_code})'"
    end

    it 'should report success' do
      begin
        @script.should_receive(:packages).and_return(nil)
        @script.should_receive(:source).and_return(format_script_text(0))
        @script.should_receive(:display_version).and_return('HEAD')
        @sequence = RightScale::ExecutableSequence.new(@bundle)
        flexmock(@sequence).should_receive(:install_packages).and_return(true)
        attachment = flexmock('A1')
        attachment.should_receive(:file_name).at_least.once.and_return('test_download')
        attachment.should_receive(:url).at_least.once.and_return("file://#{@attachment_file}")
        @script.should_receive(:attachments).at_least.once.and_return([ attachment ])
        @auditor.should_receive(:append_error).and_return{|a| puts a.inspect }.never
        result = run_sequence
        @sequence.failure_message.should == nil
        result.should be_true
      ensure
        @sequence = nil
      end
    end

    it 'should audit failures' do
      @script.should_receive(:packages).and_return(nil)
      @script.should_receive(:source).and_return(format_script_text(1))
      @script.should_receive(:display_version).and_return('Rev 1')
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      flexmock(@sequence).should_receive(:install_packages).and_return(true)
      attachment = flexmock('A2')
      attachment.should_receive(:file_name).at_least.once.and_return('test_download')
      attachment.should_receive(:url).at_least.once.and_return("file://#{@attachment_file}")
      @auditor.should_receive(:append_error)
      @script.should_receive(:attachments).at_least.once.and_return([ attachment ])
      flexmock(RightScale::Log).should_receive(:error)
      result = run_sequence
      @sequence.failure_message.should_not == nil
      result.should be_false
    end

    # Beware that this test will fail if run in an internet service environment that
    # redirects 404's to one of their pages. If `curl http://thisurldoesnotexist.wrong`
    # gives back html code, that is likely the cause of this test failing.
    it 'should report invalid attachments' do
      @script.should_receive(:packages).and_return(nil)
      @script.should_receive(:source).and_return(format_script_text(0))
      @script.should_receive(:display_version).and_return('HEAD')
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      attachment = flexmock('A3')
      attachment.should_receive(:url).and_return("http://127.0.0.1:65534")
      attachment.should_receive(:file_name).and_return("<FILENAME>") # to display any error message
      downloader = RightScale::Downloader.new(retry_period=0.1, use_backoff=false)
      @sequence.instance_variable_set(:@downloader, downloader)
      @script.should_receive(:attachments).at_least.once.and_return([ attachment ])
      @auditor.should_receive(:append_error)
      @sequence.failure_title.should be_nil
      @sequence.failure_message.should be_nil
      run_sequence.should be_false
      @sequence.failure_title.should_not be_nil
      @sequence.failure_message.should_not be_nil
    end

    it 'should retry if ohai is not ready' do
      begin
        @script.should_receive(:packages).and_return(nil)
        @script.should_receive(:source).and_return(format_script_text(0))
        @script.should_receive(:display_version).and_return('HEAD')
        @sequence = RightScale::ExecutableSequence.new(@bundle)
        flexmock(@sequence).should_receive(:install_packages).and_return(true)
        @script.should_receive(:attachments).at_least.once.and_return([])
        @auditor.should_receive(:append_error).never

        # force check_ohai to retry.
        mock_ohai = nil
        flexmock(@sequence).should_receive(:create_ohai).twice.and_return do
          if mock_ohai
            mock_ohai[:hostname] = 'hostname'
          else
            mock_ohai = {}
          end
          mock_ohai
        end
        result = run_sequence
        @sequence.failure_message.should == nil
        result.should be_true
        mock_ohai.should == { :hostname => 'hostname' }
      ensure
        @sequence = nil
      end
    end

  end

  context 'Chef error formatting' do

    before(:each) do
      # For ReposeDownloader
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with("hostname", 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "hostname", "1.2.3.4", 2, 1, 6], ["AF_INET", 443, "hostname", "5.6.7.8", 2, 1, 6]])

      # mock the cookbook checkout location
      @cookbooks_path = Dir.mktmpdir
      flexmock(RightScale::CookState).should_receive(:cookbooks_path).and_return(@cookbooks_path)

      runlist_policy = flexmock('runlist_policy')
      runlist_policy.should_receive(:thread_name).and_return(RightScale::AgentConfig.default_thread_name)
      runlist_policy.should_receive(:thread_name=).and_return(true)
      runlist_policy.should_receive(:policy_name).and_return(nil)

      bundle = flexmock('ExecutableBundle')
      bundle.should_receive(:repose_servers).and_return(['hostname']).by_default
      bundle.should_receive(:runlist_policy).and_return(runlist_policy)
      bundle.should_ignore_missing
      @sequence = RightScale::ExecutableSequence.new(bundle)
      begin
        fourty_two
      rescue Exception => e
        @exception = e
      end
      @lines = [ '    paths.size.should == 1',
                 '    paths.first.should == @sequence.send(:cookbook_repo_directory, repo)',
                 '  end',
                 '',
                 "  it 'should calculate cookbooks path for repositories with cookbooks_path' do",
                 "    repo = RightScale::CookbookRepository.new('git', 'url', 'tag', ['cookbooks_path'])",
                 '    paths = @sequence.send(:cookbooks_path, repo)',
                 '    paths.size.should == 1',
                 "    paths.first.should == File.join(@sequence.send(:cookbook_repo_directory, repo), 'cookbooks_path')",
                 '  end' ]
    end

    after(:each) do
      FileUtils.rm_rf(@cookbooks_path)
    end

    it 'should format lines of code for error message context' do
      @sequence.__send__(:context_line, @lines, 3, 0).should == '3 ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 3, 1).should == '3 ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 3, 2).should == '3  ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 3, 1, '*').should == '* ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 10, 1).should == '10 ' + @lines[9]
      @sequence.__send__(:context_line, @lines, 10, 1, '*').should == '** ' + @lines[9]
    end

    it 'should format chef error messages' do
      msg = @sequence.__send__(:chef_error, @exception)
      msg.should_not be_empty
      msg.should =~ /while executing/
    end

  end

  context 'Specific Chef error formatting' do
    before(:each) do
      # For ReposeDownloader
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with("hostname", 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "hostname", "1.2.3.4", 2, 1, 6], ["AF_INET", 443, "hostname", "5.6.7.8", 2, 1, 6]])

      # mock the cookbook checkout location
      @cookbooks_path = Dir.mktmpdir
      flexmock(RightScale::CookState).should_receive(:cookbooks_path).and_return(@cookbooks_path)

      runlist_policy = flexmock('runlist_policy')
      runlist_policy.should_receive(:thread_name).and_return(RightScale::AgentConfig.default_thread_name)
      runlist_policy.should_receive(:thread_name=).and_return(true)
      runlist_policy.should_receive(:policy_name).and_return(nil)
      
      bundle = flexmock('ExecutableBundle')
      bundle.should_receive(:repose_servers).and_return(['hostname']).by_default
      bundle.should_ignore_missing
      bundle.should_receive(:runlist_policy).and_return(runlist_policy)
      @sequence = RightScale::ExecutableSequence.new(bundle)
    end

    after(:each) do
      FileUtils.rm_rf(@cookbooks_path)
    end

    it 'should produce a readable message when cookbook does not contain a referenced resource' do
      exception_string = 'Option action must be equal to one of: nothing, url_encode!  You passed :does_not_exist.'
      exception = Chef::Exceptions::ValidationFailed.new(exception_string)
      msg = @sequence.__send__(:chef_error, exception)
      msg.should == "[chef] recipe references an action that does not exist.  Option action must be equal to one of: nothing, url_encode!  You passed :does_not_exist."
    end

    it 'should produce a readable message when the implementation of a referenced resource action does not exist' do
      exception_string = "undefined method 'action_does_not_exist' for #<TestCookbookErrorNoscript:0x9999999>"
      exception = NoMethodError.new(exception_string, 'action_does_not_exist')
      msg = @sequence.__send__(:chef_error, exception)
      msg.should == "[chef] recipe references the action <does_not_exist> which is missing an implementation"
    end
  end
end
