require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'instance_lib'
require 'executable_sequence'

describe RightScale::ExecutableSequence do

  include RightScale::SpecHelpers

  before(:all) do
    RightScale::RightLinkLog.logger.stub!(:debug)
    @attachment_file = '__test_download__'
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
    @attachment.stub!(:file_name).and_return('test_download')
    @attachment.stub!(:url).and_return("file://#{@attachment_file}")

    @script = mock('RightScript')
    @script.stub!(:nickname).and_return('__TestScript')
    @script.stub!(:parameters).and_return({})
    @script.stub!(:attachments).and_return([ @attachment ])
    @script.stub!(:packages).and_return(nil)
    @script.stub!(:is_a?).with(RightScale::RightScriptInstantiation).and_return(true)
    @script.stub!(:is_a?).with(RightScale::RecipeInstantiation).and_return(false)

    @bundle = RightScale::ExecutableBundle.new([ @script ], [], 0)

    @auditor = mock('Auditor')
    @auditor.should_receive(:audit_id).any_number_of_times.and_return(1)
    @auditor.should_receive(:create_new_section).any_number_of_times
    @auditor.should_receive(:append_info).any_number_of_times    
    @auditor.should_receive(:update_status).any_number_of_times    
    RightScale::AuditorProxy.stub!(:new).and_return(@auditor)
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
    @script.stub!(:source).and_return("#!/bin/sh\nruby -e 'exit(0)'")
    @sequence = RightScale::ExecutableSequence.new(@bundle)
    @auditor.should_receive(:append_error).never
    run_sequence.should be_true
  end

  it 'should audit failures' do
    @script.stub!(:source).and_return("#!/bin/sh\nruby -e 'exit(1)'")
    @sequence = RightScale::ExecutableSequence.new(@bundle)
    @auditor.should_receive(:append_error).exactly(3).times
    RightScale::RightLinkLog.logger.should_receive(:error)
    run_sequence.should be_false
  end

  it 'should report invalid attachments' do
    @script.stub!(:source).and_return("#!/bin/sh\nruby -e 'exit(0)'")
    @sequence = RightScale::ExecutableSequence.new(@bundle)
    @attachment.stub!(:url).and_return("http://thisurldoesnotexist.wrong")
    downloader = RightScale::Downloader.new(retry_period=0.1, use_backoff=false)
    @sequence.instance_variable_set(:@downloader, downloader)
    @auditor.should_receive(:append_error).exactly(2).times
    RightScale::RightLinkLog.logger.should_receive(:error)
    run_sequence.should be_false
  end

  it 'should report invalid packages' do
    @script.stub!(:source).and_return("#!/bin/sh\nruby -e 'exit(0)'")
    @sequence = RightScale::ExecutableSequence.new(@bundle)
    @script.stub!(:packages).and_return("__INVALID__")
    @auditor.should_receive(:append_error).exactly(2).times
    RightScale::RightLinkLog.logger.should_receive(:error)
    run_sequence.should be_false
  end
 
end