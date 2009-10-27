require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'instance_lib'
require 'executable_sequence'

describe RightScale::ExecutableSequence do

  include RightScale::SpecHelpers

  context 'Testing sequence execution' do

    before(:all) do
      RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
      @attachment_file = File.expand_path(File.join(File.dirname(__FILE__), '__test_download__'))
      File.open(@attachment_file, 'w') do |f|
        f.write('Some attachment content')
      end
      setup_state
      setup_script_execution
      @cache_dir = File.join(File.dirname(__FILE__), '__cache')
      Chef::Resource::RightScript.const_set(:DEFAULT_CACHE_DIR_ROOT, @cache_dir)
    end

    before(:each) do
      @attachment = mock('Attachment')

      @script = mock('RightScript')
      @script.should_receive(:nickname).at_least(1).times.and_return('__TestScript')
      @script.should_receive(:parameters).and_return({})
      @script.should_receive(:attachments).at_least(1).times.and_return([ @attachment ])
      @script.should_receive(:is_a?).with(RightScale::RightScriptInstantiation).and_return(true)
      @script.should_receive(:is_a?).with(RightScale::RecipeInstantiation).and_return(false)

      @bundle = RightScale::ExecutableBundle.new([ @script ], [], 0)

      @auditor = mock('Auditor')
      @auditor.should_receive(:audit_id).any_number_of_times.and_return(1)
      @auditor.should_receive(:create_new_section).any_number_of_times
      @auditor.should_receive(:append_info).any_number_of_times
      @auditor.should_receive(:update_status).any_number_of_times
      RightScale::AuditorProxy.should_receive(:new).at_least(1).times.and_return(@auditor)
    end

    after(:all) do
      cleanup_state
      cleanup_script_execution
      FileUtils.rm(@attachment_file) if @attachment_file
      FileUtils.rm_rf(@cache_dir) if @cache_dir
    end

    # Run sequence and print out exceptions
    def run_sequence
      res = false
      EM.run do
        EM.next_tick do
          Thread.new do
            begin
              res = @sequence.run
            rescue Exception => e
              puts e.message + "\n" + e.backtrace.join("\n")
            ensure
              EM.next_tick { EM.stop }
            end
          end
        end
      end
      res
    end

    it 'should report success' do
      @script.should_receive(:packages).any_number_of_times.and_return(nil)
      @script.should_receive(:source).and_return("#!/bin/sh\nruby -e 'exit(0)'")
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      @sequence.should_receive(:install_packages).and_return(true)
      @attachment.should_receive(:file_name).at_least(1).times.and_return('test_download')
      @attachment.should_receive(:url).at_least(1).times.and_return("file://#{@attachment_file}")
      @auditor.should_receive(:append_error).never
      run_sequence.should be_true
    end

    it 'should audit failures' do
      @script.should_receive(:packages).any_number_of_times.and_return(nil)
      @script.should_receive(:source).and_return("#!/bin/sh\nruby -e 'exit(1)'")
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      @sequence.should_receive(:install_packages).and_return(true)
      @attachment.should_receive(:file_name).at_least(1).times.and_return('test_download')
      @attachment.should_receive(:url).at_least(1).times.and_return("file://#{@attachment_file}")
      @auditor.should_receive(:append_error).any_number_of_times
      RightScale::RightLinkLog.logger.should_receive(:error)
      run_sequence.should be_false
    end

    it 'should report invalid attachments' do
      @script.should_receive(:packages).any_number_of_times.and_return(nil)
      @script.should_receive(:source).and_return("#!/bin/sh\nruby -e 'exit(0)'")
      @sequence = RightScale::ExecutableSequence.new(@bundle)
      @attachment.should_receive(:url).and_return("http://thisurldoesnotexist.wrong")
      @attachment.should_receive(:file_name).any_number_of_times.and_return("<FILENAME>") # to display any error message
      downloader = RightScale::Downloader.new(retry_period=0.1, use_backoff=false)
      @sequence.instance_variable_set(:@downloader, downloader)
      @auditor.should_receive(:append_error).exactly(2).times
      RightScale::RightLinkLog.logger.should_receive(:error)
      run_sequence.should be_false
    end

  end

  context 'Testing helper methods' do

    before(:each) do
      bundle = mock('Bundle', :null_object => true)
      @sequence = RightScale::ExecutableSequence.new(bundle)
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
      bundle = mock('Bundle', :null_object => true)
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
      msg = @sequence.__send__(:chef_error, 'Chef recipe', 'some_recipe', @exception)
      msg.should_not be_empty
      msg.should =~ /while executing/
    end

  end

end
