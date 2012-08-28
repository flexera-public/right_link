# Copyright (c) 2009-2011 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'log_level_manager'))

module RightScale
  describe RightLinkLogLevelManager do
    def run_log_level_manager(argv)
      replace_argv(argv)
      subject.manage(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    before(:all) do
      # preserve old ARGV for posterity (although it's unlikely that anything
      # would consume it after startup).
      @old_argv = ARGV
    end

    after(:all) do
      # restore old ARGV
      replace_argv(@old_argv)
      @error = nil
      @output = nil
    end

    before(:each) do
      @error = []
      @output = []
      flexmock(subject).should_receive(:write_error).and_return { |message| @error << message; true }
      flexmock(subject).should_receive(:write_output).and_return { |message| @output << message; true }
    end

    context 'log-level option' do
      let (:short_name)     {'-l'}
      let (:long_name)      {'--log-level'}
      let (:key)            {:level}
      let (:value)          {"info"}
      let (:expected_value) {"info"}
      it_should_behave_like 'command line argument'
    end

    context 'log-level option' do
      let (:short_name)     {'-v'}
      let (:long_name)      {'--verbose'}
      let (:key)            {:verbose}
      let (:value)          {""}
      let (:expected_value) {true}
      it_should_behave_like 'command line argument'
    end

    context 'rs_log_level --version' do
      it 'should report RightLink version from gemspec' do
        run_log_level_manager('--version')
        @output.join("\n").should match /rs_log_level \d+\.\d+\.?\d* - RightLink's log level \(c\) 2011 RightScale/
      end
    end

    context 'rs_log_level --help' do
      it 'should show usage inforamtion' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'log_level_manager.rb')))
        run_log_level_manager('--help')
        @output.join("\n").should include(usage)
      end
    end

    context 'rs_log_level' do
      it 'should prints the current RightLink agent log level' do
        flexmock(subject).should_receive(:request_log_level).with(
          'instance',
          { :name => 'get_log_level' },
          { :agent_name => 'instance', :verbose => false, :level => nil, :version => false, :help => false } 
        ).and_return(true)
        run_log_level_manager([])
      end
    end

    ["debug", "info", "warn", "error", "fatal"].each do |level|
      context "rs_log_level -l #{level}" do
        it "should change log level to #{level}" do
          flexmock(subject).should_receive(:request_log_level).with(
            'instance',
            { :name => 'set_log_level', :level => level.to_sym },
            { :agent_name => 'instance', :verbose => false, :level => level, :version => false, :help => false, :level_given => true } 
          ).and_return(true)
          run_log_level_manager("-l #{level}".split)
        end
      end
    end
  end
end
