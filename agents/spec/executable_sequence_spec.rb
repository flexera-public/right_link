require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'chef', 'lib', 'plugins')
require 'instance_lib'
require 'executable_sequence'

describe RightScale::ExecutableSequence do

  include RightScale::SpecHelpers

  context 'Testing sequence execution' do

    before(:all) do
      flexmock(RightScale::RightLinkLog).should_receive(:debug)
      @attachment_file = File.expand_path(File.join(File.dirname(__FILE__), '__test_download__'))
      File.open(@attachment_file, 'w') do |f|
        f.write('Some attachment content')
      end
      platform = RightScale::RightLinkConfig[:platform]
      @cache_dir = File.expand_path(File.join(platform.filesystem.temp_dir, 'executable_sequence_spec'))
      Chef::Resource::RightScript.const_set(:DEFAULT_CACHE_DIR_ROOT, @cache_dir)
    end

    before(:each) do
      setup_state
      setup_script_execution
      @script = flexmock(:nickname => '__TestScript', :parameters => {}, :ready => true)
      @script.should_receive(:is_a?).with(RightScale::RightScriptInstantiation).and_return(true)
      @script.should_receive(:is_a?).with(RightScale::RecipeInstantiation).and_return(false)

      @bundle = RightScale::ExecutableBundle.new([ @script ], [], 0)

      @auditor = flexmock('AuditorProxy')
      @auditor.should_receive(:audit_id).and_return(1)
      @auditor.should_receive(:create_new_section)
      @auditor.should_receive(:append_info)
      @auditor.should_receive(:append_output)
      @auditor.should_receive(:update_status)
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
      EM.run do
        Thread.new do
          begin
            @sequence.callback { res = true;  EM.next_tick { EM.stop } }
            @sequence.errback  { res = false; EM.next_tick { EM.stop } }
            @sequence.run
          rescue Exception => e
            puts e.message + "\n" + e.backtrace.join("\n")
            EM.next_tick { EM.stop }
          end
        end
      end
      res
    end

    def format_script_text(exit_code)
      platform = RightScale::RightLinkConfig[:platform]
      return platform.windows? ?
             "exit #{exit_code}" :
             "#!/bin/sh\nruby -e 'exit(#{exit_code})'"
    end

    it 'should report success' do
      begin
        @script.should_receive(:packages).and_return(nil)
        @script.should_receive(:source).and_return(format_script_text(0))
        @sequence = RightScale::ExecutableSequence.new(@bundle)
        @sequence.instance_variable_set(:@auditor, @auditor)
        flexmock(@sequence).should_receive(:install_packages).and_return(true)
        attachment = flexmock('A1')
        attachment.should_receive(:file_name).at_least.once.and_return('test_download')
        attachment.should_receive(:url).at_least.once.and_return("file://#{@attachment_file}")
        @script.should_receive(:attachments).at_least.once.and_return([ attachment ])
        @auditor.should_receive(:append_error).never
        run_sequence.should be_true
      ensure
        @sequence = nil
      end
    end

    it 'should audit failures' do
      @script.should_receive(:packages).and_return(nil)
      @script.should_receive(:source).and_return(format_script_text(1))
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      @sequence.instance_variable_set(:@auditor, @auditor)
      flexmock(@sequence).should_receive(:install_packages).and_return(true)
      attachment = flexmock('A2')
      attachment.should_receive(:file_name).at_least.once.and_return('test_download')
      attachment.should_receive(:url).at_least.once.and_return("file://#{@attachment_file}")
      @auditor.should_receive(:append_error)
      @script.should_receive(:attachments).at_least.once.and_return([ attachment ])
      flexmock(RightScale::RightLinkLog).should_receive(:error)
      run_sequence.should be_false
    end

    it 'should report invalid attachments' do
      @script.should_receive(:packages).and_return(nil)
      @script.should_receive(:source).and_return(format_script_text(0))
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      @sequence.instance_variable_set(:@auditor, @auditor)
      attachment = flexmock('A3')
      attachment.should_receive(:url).and_return("http://thisurldoesnotexist.wrong")
      attachment.should_receive(:file_name).and_return("<FILENAME>") # to display any error message
      downloader = RightScale::Downloader.new(retry_period=0.1, use_backoff=false)
      @sequence.instance_variable_set(:@downloader, downloader)
      flexmock(@auditor).should_receive(:append_error).twice
      @script.should_receive(:attachments).at_least.once.and_return([ attachment ])
      flexmock(RightScale::RightLinkLog).should_receive(:error)
      run_sequence.should be_false
    end

  end

  context 'Testing helper methods' do

    before(:each) do
      bundle = flexmock('Bundle')
      bundle.should_ignore_missing
      @sequence = RightScale::ExecutableSequence.new(bundle)
      @sequence.instance_variable_set(:@auditor, @auditor)
    end

    it 'should calculate cookbooks path for repositories with no cookbooks_path' do
      repo = RightScale::CookbookRepository.new('git', 'url', 'tag')
      paths = @sequence.send(:cookbooks_path, repo)
      paths.size.should == 1
      paths.first.should == @sequence.send(:cookbook_repo_directory, repo)
      repo = RightScale::CookbookRepository.new('git', 'url', 'tag', [])
      paths = @sequence.send(:cookbooks_path, repo)
      paths.size.should == 1
      paths.first.should == @sequence.send(:cookbook_repo_directory, repo)
    end

    it 'should calculate cookbooks path for repositories with cookbooks_path' do
      repo = RightScale::CookbookRepository.new('git', 'url', 'tag', ['cookbooks_path'])
      paths = @sequence.send(:cookbooks_path, repo)
      paths.size.should == 1
      paths.first.should == File.join(@sequence.send(:cookbook_repo_directory, repo), 'cookbooks_path')
    end
  end

  context 'Chef error formatting' do

    before(:each) do
      bundle = flexmock('Bundle')
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

    it 'should format lines of code for error message context' do
      @sequence.__send__(:context_line, @lines, 3, 0).should == '3 ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 3, 1).should == '3 ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 3, 2).should == '3  ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 3, 1, '*').should == '* ' + @lines[2]
      @sequence.__send__(:context_line, @lines, 10, 1).should == '10 ' + @lines[9]
      @sequence.__send__(:context_line, @lines, 10, 1, '*').should == '** ' + @lines[9]
    end

    it 'should format chef error messages' do
      msg = @sequence.__send__(:chef_error, 'Chef recipe', @exception)
      msg.should_not be_empty
      msg.should =~ /while executing/
    end

  end

end
