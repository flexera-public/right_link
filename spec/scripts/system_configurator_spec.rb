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

  context '#configure_ssh' do
    let(:public_key) { "some fake public key material" }
    let(:user_ssh_dir) { "/root/.ssh" }
    let(:authorized_keys_file) { "#{user_ssh_dir}/authorized_keys" }

    it "logs a warning if public key is empty string" do
      ENV['VS_SSH_PUBLIC_KEY'] = ""
      subject.configure_root_access
      @output.should include "No public SSH key found in metadata"
    end

    it "logs a warning if no public key is specified" do
      ENV['VS_SSH_PUBLIC_KEY'] = nil
      subject.configure_root_access
      @output.should include "No public SSH key found in metadata"
    end


    it "appends public key to /root/.ssh/authorized_keys file" do
      ENV['VS_SSH_PUBLIC_KEY'] = public_key
      flexmock(::FileUtils).should_receive(:mkdir_p).with(user_ssh_dir)
      flexmock(::FileUtils).should_receive(:chmod).with(0600, authorized_keys_file)
      flexmock(::File).should_receive(:exists?).and_return(false)
      flexmock(::File).should_receive(:open, "a").and_return(true)
      subject.configure_root_access
      @output.should include "Appending public ssh key to #{authorized_keys_file}"
    end

    it "does nothing if key is already authorized" do
      ENV['VS_SSH_PUBLIC_KEY'] = public_key
      ssh_keys_file = flexmock("authorized_keys_file")
      ssh_keys_file.should_receive(:each_line).and_yield(public_key)
      flexmock(::FileUtils).should_receive(:mkdir_p).with(user_ssh_dir)
      flexmock(::FileUtils).should_receive(:chmod).with(0600, authorized_keys_file)
      flexmock(::File).should_receive(:exists?).and_return(true)
      flexmock(::File).should_receive(:open).and_yield(ssh_keys_file)
      subject.configure_root_access
      @output.should include "Public ssh key for root already exists in #{authorized_keys_file}"
    end
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
