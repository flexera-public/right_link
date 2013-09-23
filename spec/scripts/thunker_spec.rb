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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'thunker'))

module RightScale
  describe Thunker do
    def run_thunker(argv)
      replace_argv(argv)
      flexmock(subject).should_receive(:check_privileges).and_return(true)
      opts = subject.parse_args
      subject.run(opts)
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
      [subject, STDOUT, STDERR].each do |subj|
        flexmock(subj).should_receive(:puts).and_return { |message| @output << message; true }
        flexmock(subj).should_receive(:print).and_return { |message| @output << message; true }
      end
    end
    context 'uuid option' do
      let(:short_name)    {'-i'}
      let(:long_name)     {'--uuid'}
      let(:key)           {:uuid}
      let(:value)         {'uuid'}
      let(:expected_value){value}
      it_should_behave_like 'command line argument'
    end

    context 'username option' do
      let(:short_name)    {'-u'}
      let(:long_name)     {'--username'}
      let(:key)           {:username}
      let(:value)         {'username'}
      let(:expected_value){value}
      it_should_behave_like 'command line argument'
    end

    context 'email option' do
      let(:short_name)    {'-e'}
      let(:long_name)     {'--email'}
      let(:key)           {:email}
      let(:value)         {'email'}
      let(:expected_value){value}
      it_should_behave_like 'command line argument'
    end

    context 'profile option' do
      let(:short_name)    {'-p'}
      let(:long_name)     {'--profile'}
      let(:key)           {:profile}
      let(:value)         {'profile'}
      let(:expected_value){value}
      it_should_behave_like 'command line argument'
    end

    context 'force option' do
      let(:short_name)    {'-f'}
      let(:long_name)     {'--force'}
      let(:key)           {:force}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'superuser option' do
      let(:short_name)    {'-s'}
      let(:long_name)     {'--superuser'}
      let(:key)           {:superuser}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'rs_thunk --version' do
      it 'should reports RightLink version from gemspec' do
        run_thunker('--version')
        @output.join("\n").should match /rs_thunk \d+\.\d+\.?\d* - RightLink's thunker \(c\) 201\d RightScale/
      end
    end

    context 'rs_thunk --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'thunker.rb')))
        run_thunker('--help')
        @output.join("\n").should include(usage)
      end
    end

    def create_user(superuser=false, profile_data=nil, force=false)
      subject.should_receive(:fail).and_return { raise }
      flexmock(LoginUserManager.instance).should_receive(:create_user).with("USER", "123", superuser, Proc).and_return("USER")
      subject.should_receive(:create_audit_entry).with("EMAIL@EMAIL.COM", "USER", FlexMock.any, FlexMock.any, FlexMock.any)
      subject.should_receive(:display_motd)
      flexmock(subject).should_receive(:chown_tty).and_return(true)
      flexmock(Kernel).should_receive(:exec).with('sudo', '-i', '-u', "USER")
      args = '--username USER --uuid 123 --email EMAIL@EMAIL.COM'.split
      args.push('-s') if superuser
      args.push('-p', profile_data) if profile_data
      args.push('-f') if force
      run_thunker(args)
    end

    context 'rs_thunk --username USER --uuid 123 --email EMAIL@EMAIL.COM' do
      it 'should create account' do
        create_user
      end
    end

    context 'rs_thunk --username USER --uuid 123 --email EMAIL@EMAIL.COM -p URL' do
      it 'should create account and use extra profile data' do
        create_user(false, "URL")
      end
    end

    context 'rs_thunk --username USER --uuid 123 --email EMAIL@EMAIL.COM -p URL -f' do
      it 'should create account and use extra profile data and rewrite existing files' do
        create_user(false, "URL", true)
      end
    end
  end
end
