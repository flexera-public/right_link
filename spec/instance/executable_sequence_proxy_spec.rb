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

describe RightScale::ExecutableSequenceProxy do

  include RightScale::SpecHelper

  it_should_behave_like 'mocks cook'

  let(:thread_name)   {'some_thread_name'}
  let(:policy_name)   {'some_policy_name'}
  let(:pid_container) { [] }

  let(:runlist_policy) do
    flexmock('runlist policy',
             :thread_name => thread_name,
             :policy_name => policy_name,
             :audit_period => 120)
  end

  let(:bundle) do
    result = flexmock('bundle', :runlist_policy => @runlist_policy)
    result.should_receive(:to_json).and_return("[\"some json\"]")
    result
  end

  let(:audit) do
    result = flexmock('audit', :append_info => true)
    result.should_receive(:create_new_section).with('Querying tags')
    result.should_receive(:append_info).with('No tags discovered.').by_default
    result.should_receive(:update_status)
    result
  end

  let(:context) do
    result = flexmock('context',
                      :audit             => audit,
                      :payload           => bundle,
                      :decommission?     => !!decommission_type,
                      :decommission_type => decommission_type,
                      :thread_name       => thread_name)
    result.should_receive(:succeeded=)
    result
  end

  let(:tag_manager) do
    result = flexmock('agent tag manager')
    result.should_receive(:tags).and_yield([]).by_default
    result
  end

  subject do
    pids = pid_container
    described_class.new(
      context, :pid_callback => lambda { |sequence| pids << sequence.pid })
  end

  before(:each) do
    setup_state('rs-instance-1-1')

    # mock agent tag manager, with some default expectations to handle happy
    # path for startup tag query
    flexmock(::RightScale::AgentTagManager).
      should_receive(:instance).
      and_return(tag_manager)
  end

  after(:each) do
    cleanup_state
  end

  context 'tag query' do
    context 'when the instance has tags' do
      let(:tags) { %w{foo bar baz} }

      it 'should audit the tags' do
        tag_manager.should_receive(:tags).and_yield(tags)
        audit.should_receive(:append_info).with("Tags discovered: '#{tags.join(', ')}'")
      end
    end

    context 'when the query fails or times out' do
      it 'should audit and log the failure' do
        tag_manager.should_receive(:tags).and_yield('fall down go boom :(')
        flexmock(RightScale::Log).should_receive(:error).with(/fall down go boom/)
        audit.should_receive(:append_error).with('Could not discover tags due to an error or timeout.')
      end
    end
  end

  def assert_succeeded
    expected_environment = { 
      ::RightScale::OptionsBag::OPTIONS_ENV => nil
    }
    if RightScale::Platform.windows?
      expected_environment[::RightScale::ExecutableSequenceProxy::DECRYPTION_KEY_NAME] = "secretpw"
    end

    status = flexmock('status', :success? => true)
    actual_environment = nil
    flexmock(::RightScale::RightPopen).should_receive(:popen3_async).and_return do |cmd, o|
      actual_environment = o[:environment]
      o[:target].instance_variable_set(:@audit_closed, true)
      o[:target].send(o[:pid_handler], 123)
      o[:target].send(o[:exit_handler], status)
      true
    end
    flexmock(subject).should_receive(:random_password).and_return("secretpw")

    subject.instance_variable_get(:@deferred_status).should == nil
    run_em_test { subject.run; stop_em_test }
    subject.instance_variable_get(:@deferred_status).should == :succeeded
    subject.thread_name.should == thread_name
    subject.pid.should == 123
    subject.pid.should == pid_container.first
    actual_environment.should == expected_environment
  end

  context 'with a boot or operational context' do
    let(:decommission_type) { nil }

    it 'should run a valid command' do
      assert_succeeded
    end

    it 'should find the cook utility' do
      status = flexmock('status', :success? => true)
      cmd_ = nil
      flexmock(RightScale::RightPopen).should_receive(:popen3_async).and_return do |cmd, o|
        cmd_ = cmd
        o[:target].instance_variable_set(:@audit_closed, true)
        o[:target].send(o[:exit_handler], status)
        true
      end
      run_em_test { subject.run; stop_em_test }

      # note that normalize_path makes it tricky to guess at full command string
      # so it is best to rely on config constants.
      cook_util_path = File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'bin', 'cook_runner'))
      expected = "#{File.basename(RightScale::AgentConfig.ruby_cmd)} \"#{cook_util_path}\""
      if RightScale::Platform.windows?
        matcher = Regexp.compile(".*" + Regexp.escape(" /C type ") + ".*" + Regexp.escape("rs_executable_sequence#{thread_name}.txt\" | ") + ".*" + Regexp.escape(expected))
      else
        matcher = Regexp.compile(".*" + Regexp.escape(expected))
      end
      cmd_.should match matcher
    end

    it 'should report failures when cook fails' do
      status = flexmock('status', :success? => false, :exitstatus => 1)
      flexmock(RightScale::RightPopen).should_receive(:popen3_async).and_return do |cmd, o|
        o[:target].instance_variable_set(:@audit_closed, true)
        o[:target].send(o[:exit_handler], status)
        true
      end
      audit.should_receive(:append_error).once
      subject.instance_variable_get(:@deferred_status).should == nil
      run_em_test { subject.run; stop_em_test }
      subject.instance_variable_get(:@deferred_status).should == :failed
    end

    context 'when actually running popen3_async' do
      it 'should call the cook utility' do
        mock_output = File.join(File.dirname(__FILE__), 'cook_mock_output')
        File.delete(mock_output) if File.exists?(mock_output)
        flexmock(subject).instance_variable_set(:@audit_closed, true)
        flexmock(subject).should_receive(:cook_path).and_return(File.join(File.dirname(__FILE__), 'cook_mock.rb'))
        flexmock(subject).should_receive(:random_password).and_return("secretpw")
        flexmock(subject).should_receive(:succeed).and_return { |*args| stop_em_test }
        flexmock(subject).should_receive(:report_failure).and_return { |*args| puts args.inspect; stop_em_test }
        run_em_test { subject.run }
        pid_container.should_not be_empty
        pid_container.first.should > 0
        begin
          output = File.read(mock_output)
          # the spec setup does some weird stuff with the jsonization of the bundle, so we jump though hoops here to match what was
          # actually sent to the cook utility
          if RightScale::Platform.windows?
            RightScale::MessageEncoder::SecretSerializer.new('rs-instance-1-1', 'secretpw').load(output).to_json.should == bundle.to_json
          end
        ensure
          (File.delete(mock_output) if File.file?(mock_output)) rescue nil
        end
      end

    end
  end

  context 'with a decommission context and known type' do
    let(:decommission_type) { ::RightScale::ShutdownRequest::STOP }

    it 'should run a valid command' do
      assert_succeeded
    end
  end

  context 'with a decommission context and unknown type' do
    let(:decommission_type) { 'unknown' }

    it 'should run a valid command' do
      assert_succeeded
    end
  end
end
