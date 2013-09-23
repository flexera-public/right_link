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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'agent_checker'))
require 'pp'

module RightScale
  describe AgentChecker do
    def run_agent_checker(args)
      replace_argv(args)
      opts = subject.parse_args
      subject.should_receive(:stop_agent_watcher)
      subject.start(opts)
      return 0
    rescue SystemExit => e
      return e.status
    end

    def setup(hide_exception=false, retries=0)
      flexmock(subject).should_receive(:error).and_return { raise } unless hide_exception
      flexmock(subject).should_receive(:setup_traps).once
      agent = { :identity => "test", :pid_dir => "/tmp", :listen_port => 123, :cookie => 123}
      flexmock(AgentConfig).should_receive(:agent_state_dir).and_return('/no/such/directory')
      flexmock(AgentConfig).should_receive(:agent_options).with('instance').and_return(agent).times(retries + 1)
      flexmock(Log).should_receive(:program_name=)
      flexmock(Log).should_receive(:facility=)
      flexmock(Log).should_receive(:log_to_file_only)
      flexmock(Log).should_receive(:init)
      flexmock(Log).should_receive(:level=)
      one_shot_timer = flexmock('timer')
      one_shot_timer.should_receive(:cancel).and_return(true)
      flexmock(EM).should_receive(:add_timer).with(Fixnum, Proc).and_return { |interval, callback| callback.call; one_shot_timer }
      flexmock(EM).should_receive(:error_handler)
      flexmock(EM).should_receive(:run).with(Proc).and_return { |block| block.call }.once
      pid_file = flexmock("PidFile")
      use_agent_watcher = !RightScale::Platform.windows?
      pid_file_agent = use_agent_watcher ? flexmock("PidFile") : nil
      flexmock(PidFile).should_receive(:new).with("test-rchk", "/tmp").and_return(pid_file).once
      flexmock(PidFile).should_receive(:new).with("test", "/tmp").and_return(pid_file_agent).once if pid_file_agent

      [pid_file, pid_file_agent]
    end

    def start(options={}, additional_args=nil)
      pid_file, pid_file_agent = setup
      time_limit = options[:time_limit] || AgentChecker::DEFAULT_TIME_LIMIT
      pid_file.should_receive(:check)
      subject.should_receive(:daemonize)
      pid_file.should_receive(:write)
      pid_file.should_receive(:remove)

      agent_running = options[:start_agent] ? false : true
      pid_file_agent.should_receive(:check).and_return {
        raise PidFile::AlreadyRunning if agent_running
        false
      } if pid_file_agent

      flexmock(CommandRunner).should_receive(:start)
      flexmock(EM).should_receive(:add_periodic_timer)\
                  .once\
                  .with(time_limit, Proc)\
                  .and_return { |time_limit, block| block.call}
      flexmock(subject).should_receive(:send_command).with({:name => "check_connectivity"}, false, AgentChecker::COMMAND_IO_TIMEOUT, Proc)
      flexmock(EM::Timer).should_receive(:new).with(options[:retry_interval] || AgentChecker::DEFAULT_RETRY_INTERVAL, Proc)
      args = "--start"
      args = "#{args} #{additional_args}" if additional_args
      run_agent_checker(args.split)
    end

    def stop()
      pid_file, pid_file_agent = setup
      if RightScale::Platform::windows?
        pid_file.should_receive(:read_pid).and_return(:pid => 123, :listen_port => 123, :cookie => 123).once
        flexmock(subject).should_receive(:send_command).with({:name => :terminate}, verbose = false, timeout = 30, Proc).once
      else
        pid_file.should_receive(:read_pid).and_return(:pid => 123).once
        pid_file_agent.should_receive(:check).and_return(false) if pid_file_agent
        flexmock(Process).should_receive(:kill).with('TERM', 123).once
        subject.should_receive(:terminate)
      end
      run_agent_checker("--stop")
    end

    def ping(verbose=false)
      setup
      flexmock(subject).should_receive(:send_command).with({:name => "check_connectivity"}, verbose, AgentChecker::COMMAND_IO_TIMEOUT, Proc).once
      flexmock(EM::Timer).should_receive(:new)
      args = ['--ping']
      args.push('-v') if verbose
      run_agent_checker(args)
    end

    before(:all) do
      # preserve old ARGV for posterity (although it's unlikely that anything
      # would consume it after startup).
      @old_argv = ARGV
    end

    after(:all) do
      # restore old ARGV
      replace_argv(@old_argv)
      @output = nil
    end

    before(:each) do
      @output = []
      flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(STDOUT).should_receive(:print).and_return { |message| @output << message; true }
    end

    context 'attempts option' do
      let(:short_name)    {'-a'}
      let(:long_name)     {'--attempts'}
      let(:key)           {:max_attempts}
      let(:value)         {'400'}
      let(:expected_value){400}
      it_should_behave_like 'command line argument'
    end

    context 'retry-interval option' do
      let(:short_name)    {'-r'}
      let(:long_name)     {'--retry-interval'}
      let(:key)           {:retry_interval}
      let(:value)         {'400'}
      let(:expected_value){400}
      it_should_behave_like 'command line argument'
    end

    context 'time-limit option' do
      let(:short_name)    {'-t'}
      let(:long_name)     {'--time-limit'}
      let(:key)           {:time_limit}
      let(:value)         {'400'}
      let(:expected_value){400}
      it_should_behave_like 'command line argument'
    end

    context 'start option' do
      let(:short_name)    {'--start'}
      let(:long_name)     {'--start'}
      let(:key)           {:daemon}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'stop option' do
      let(:short_name)    {'--stop'}
      let(:long_name)     {'--stop'}
      let(:key)           {:stop}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'ping option' do
      let(:short_name)    {'-p'}
      let(:long_name)     {'--ping'}
      let(:key)           {:ping}
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

    context 'state-path option' do
      let(:short_name)    {'--state-path'}
      let(:long_name)     {'--state-path'}
      let(:key)           {:state_path}
      let(:value)         {'state_path'}
      let(:expected_value){value}
      it_should_behave_like 'command line argument'
    end

    context 'rchk --version' do
      it 'should reports RightLink version from gemspec' do
        run_agent_checker('--version')
        @output.join("\n").should match /rchk \d+\.\d+\.?\d* - RightScale Agent Checker \(c\) 201\d RightScale/
      end
    end

    context 'rchk --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'agent_checker.rb')))
        run_agent_checker('--help')
        @output.join("\n").should include(usage)
      end
    end

    context 'rchk --start' do
      it 'it should run a daemon process' do
        start
      end
    end

    context 'rchk --start' do
      it 'it should run a daemon process and also start the agent' do
        start({ :start_agent => true })
      end
    end

    context 'rchk --start --time-limit 600' do
      it 'should run a daemon and override the default time limit since last communication for check to pass' do
        start({ :time_limit => 600 }, "--time-limit 600")
      end
    end

    context 'rchk --start --retry_interval 600' do
      it 'should override the default interval for retrying communication check' do
        start({ :retry_interval => 600 }, '--retry-interval 600')
      end
    end

    context 'rchk --stop' do
      it 'should stop the currently running daemon' do
        stop
      end
    end

    context 'rchk --ping' do
      it 'should try communicating' do
        ping
      end
    end

    context 'rchk --ping -v' do
      it 'should try communicating and dispaly debug information' do
        ping(true)
      end
    end

    context 'rchk --ping --attempts 5' do
      it 'should make requested number of attempts' do
        attempts = 5
        setup(hide_exception=true, attempts)
        flexmock(subject).should_receive(:send_command)\
              .times(attempts)\
              .with({:name => "check_connectivity"}, false, AgentChecker::COMMAND_IO_TIMEOUT, Proc)\
              .and_return { raise Exception, "test" }
        subject.should_receive(:reenroll!).once
        run_agent_checker("--ping --attempts #{attempts}".split)
      end
    end
  end
end
