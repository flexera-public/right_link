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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'shutdown_client'))

module RightScale
  describe ShutdownClient do

    def run_shutdown_client(argv)
      replace_argv(argv)
      flexmock(subject).should_receive(:fail_if_right_agent_is_not_running).and_return(true)
      flexmock(subject).should_receive(:check_privileges).and_return(true)
      subject.run(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    def send_command(args, level, immediate=false)
      flexmock(AgentConfig).should_receive(:agent_options).and_return({:listen_port => 123})
      flexmock(subject).should_receive(:send_command).with({
        :name => :set_shutdown_request,
        :level => level,
        :immediately => immediate
      }, false, Proc).once
      run_shutdown_client(Array(args))
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

    context 'reboot option' do
      let(:short_name)    {'-r'}
      let(:long_name)     {'--reboot'}
      let(:key)           {:reboot}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'stop option' do
      let(:short_name)    {'-s'}
      let(:long_name)     {'--stop'}
      let(:key)           {:stop}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'terminate option' do
      let(:short_name)    {'-t'}
      let(:long_name)     {'--terminate'}
      let(:key)           {:terminate}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'immediately option' do
      let(:short_name)    {'-i'}
      let(:long_name)     {'--immediately'}
      let(:key)           {:immediately}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'deferred option' do
      let(:short_name)    {'-d'}
      let(:long_name)     {'--deferred'}
      let(:key)           {:deferred}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'verbose option' do
      let(:short_name)    {'-v'}
      let(:long_name)     {'--verbose'}
      let(:key)           {:verbose}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'rs_shutdown --version' do
      it 'should reports RightLink version from gemspec' do
        run_shutdown_client('--version')
        @output.join('\n').should match /rs_shutdown \d+\.\d+\.?\d* - RightLink's shutdown client \(c\) \d+ RightScale/
      end
    end

    context 'rs_shutdown --help' do
      it 'should show usage inforamtion' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'shutdown_client.rb')))
        run_shutdown_client('--help')
        @output.join('\n').should include(usage)
      end
    end

    context 'rs_shutdown -s -i -d' do
      it 'should report about conflictin options' do
        run_shutdown_client(["-s", "-i", "-d"])
        @output.join('\n').should include("--deferred conflicts with --immediately")
      end
    end

    context 'rs_shutdown -s' do
      it 'should shutdown' do
        send_command('-s', ::RightScale::ShutdownRequest::STOP)
      end
    end

    context 'rs_shutdown -s -i' do
      it 'should shutdown immediately' do
        send_command(['-s', '-i'], ::RightScale::ShutdownRequest::STOP, true)
      end
    end

    context 'rs_shutdown -r' do
      it 'should reboot' do
        send_command('-r', ::RightScale::ShutdownRequest::REBOOT)
      end
    end

    context 'rs_shutdown -r -i' do
      it 'should reboot immediately' do
        send_command(['-r', '-i'], ::RightScale::ShutdownRequest::REBOOT, true)
      end
    end

    context 'rs_shutdown -t' do
      it 'should terminate' do
        send_command('-t', ::RightScale::ShutdownRequest::TERMINATE)
      end
    end

    context 'rs_shutdown -t -i' do
      it 'should terminate immediately' do
        send_command(['-t', '-i'], ::RightScale::ShutdownRequest::TERMINATE, true)
      end
    end

  end
end
