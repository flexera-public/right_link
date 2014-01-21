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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'system_configurator'))

describe RightScale::SystemConfigurator do
  context '.run' do
    it 'should read the options file'
    it 'should specify some default options'
    it 'should call the appropriate action function'
    it 'should return 2 if the action is disabled'
    it 'should return 1 on failure'
    it 'should return 0 on success'
  end

  context '#configure_ssh' do
    it 'should be tested'
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
    flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
    flexmock(STDOUT).should_receive(:print).and_return { |message| @output << message; true }
  end

  def run_system_configurator(args)
    replace_argv(args)
    subject.start(subject.parse_args)
    return 0
  rescue SystemExit => e
    return e.status
  end

  context 'action option' do
    let(:short_name)    {'--action'}
    let(:long_name)     {'--action'}
    let(:key)           {:action}
    let(:value)         {'hostname'}
    let(:expected_value){value}
    it_should_behave_like 'command line argument'
  end

  context 'system --help' do
    it 'should show usage info' do
      usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'system_configurator.rb')))
      run_system_configurator('--help')
      @output.join("\n").should include(usage)
    end
  end

  ["hostname", "ssh", "proxy", "network" ].each do |action|
    context "system --action=#{action}" do
      it "should configure #{action}" do
        flexmock(subject).should_receive("configure_#{action}".to_sym).once
        run_system_configurator("--action=#{action}")
      end
    end
  end


  context "system --action=wrong_action" do
    it "should fail because of wrong action" do
      expect {run_system_configurator("--action=wrong_action")}.to raise_error(StandardError)
    end
  end

end
