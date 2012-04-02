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

  let(:thread_name) {'some_thread_name'}

  before(:each) do
    setup_state('rs-instance-1-1')

    #mock audit entry
    @audit = flexmock('audit', :audit_id=>12345)
    flexmock(RightScale::AuditProxy).should_receive(:new).and_return(@audit)

    #mock policy and bundle
    @runlist_policy = flexmock('runlist policy', :thread_name => thread_name)
    @bundle = flexmock('bundle', :runlist_policy => @runlist_policy)
    @bundle.should_receive(:to_json).and_return("[\"some json\"]")
    @context = flexmock('context', :audit => @audit, :payload => @bundle, :decommission => false, :thread_name => thread_name)
    @context.should_receive(:succeeded=)

    #mock agent tag manager, with some default expectations to handle happy
    #path for startup tag query
    @tag_manager = flexmock('agent tag manager')
    flexmock(RightScale::AgentTagManager).should_receive(:instance).and_return(@tag_manager)
    @tag_manager.should_receive(:tags).and_yield([]).by_default
    @audit.should_receive(:create_new_section).with('Querying tags before converge')
    @audit.should_receive(:append_info).with('No tags discovered.').by_default
    @audit.should_receive(:update_status)

    @pid = nil
    @proxy = RightScale::ExecutableSequenceProxy.new(@context, :pid_callback => lambda { |sequence| @pid = sequence.pid })
  end

  after(:each) do
    cleanup_state
  end

  context 'tag query' do
    context 'when the instance has tags' do
      it 'should audit the tags' do
        @tag_manager.should_receive(:tags).and_yield(['foo', 'bar', 'baz'])
        @audit.should_receive(:append_info).with("Tags discovered: 'foo, bar, baz'")
      end
    end

    context 'when the query fails or times out' do
      it 'should audit and log the failure' do
        @tag_manager.should_receive(:tags).and_yield('fall down go boom :(')
        flexmock(RightScale::Log).should_receive(:error).with(/fall down go boom/)
        @audit.should_receive(:append_error).with('Could not discover tags due to an error or timeout.')
      end
    end
  end

  it 'should run a valid command' do
    status = flexmock('status', :success? => true)
    flexmock(RightScale).should_receive(:popen3).and_return do |o|
      o[:target].instance_variable_set(:@audit_closed, true)
      o[:target].send(o[:pid_handler], 123)
      o[:target].send(o[:exit_handler], status)
    end
    @proxy.instance_variable_get(:@deferred_status).should == nil
    run_em_test { @proxy.run; EM.next_tick { EM.stop } }
    @proxy.instance_variable_get(:@deferred_status).should == :succeeded
    @proxy.thread_name.should == thread_name
    @proxy.pid.should == 123
    @proxy.pid.should == @pid
  end

  it 'should find the cook utility' do
    status = flexmock('status', :success? => true)
    cmd = nil
    flexmock(RightScale).should_receive(:popen3).and_return do |o|
      cmd = o[:command]
      o[:target].instance_variable_set(:@audit_closed, true)
      o[:target].send(o[:exit_handler], status)
    end
    run_em_test { @proxy.run; EM.next_tick { EM.stop } }

    # note that normalize_path makes it tricky to guess at full command string
    # so it is best to rely on config constants.
    cook_util_path = File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'bin', 'cook_runner.rb'))
    expected = "#{File.basename(RightScale::AgentConfig.sandbox_ruby_cmd)} \"#{cook_util_path}\""
    if RightScale::Platform.windows?
      matcher = Regexp.compile(".*" + Regexp.escape(" /C type ") + ".*" + Regexp.escape("rs_executable_sequence#{thread_name}.txt\" | ") + ".*" + Regexp.escape(expected))
    else
      matcher = Regexp.compile(".*" + Regexp.escape(expected))
    end
    cmd.should match matcher
  end

  it 'should report failures when cook fails' do
    status = flexmock('status', :success? => false, :exitstatus => 1)
    flexmock(RightScale).should_receive(:popen3).and_return do |o|
      o[:target].instance_variable_set(:@audit_closed, true)
      o[:target].send(o[:exit_handler], status)
    end
    @audit.should_receive(:append_error).twice
    @proxy.instance_variable_get(:@deferred_status).should == nil
    run_em_test { @proxy.run; EM.next_tick { EM.stop } }
    @proxy.instance_variable_get(:@deferred_status).should == :failed
  end

  context 'when running popen3' do

    it 'should call the cook utility' do

      mock_output = File.join(File.dirname(__FILE__), 'cook_mock_output')
      File.delete(mock_output) if File.exists?(mock_output)
      flexmock(@proxy).instance_variable_set(:@audit_closed, true)
      flexmock(@proxy).should_receive(:cook_path).and_return(File.join(File.dirname(__FILE__), 'cook_mock.rb'))
      flexmock(@proxy).should_receive(:succeed).and_return { |*args| EM.stop }
      flexmock(@proxy).should_receive(:report_failure).and_return { |*args| puts args.inspect; EM.stop }
      run_em_test { @proxy.run }
      @pid.should_not be_nil
      @pid.should > 0
      begin
        output = File.read(mock_output)
        # the spec setup does some weird stuff with the jsonization of the bundle, so we jump though hoops here to match what was
        # actually sent to the cook utility
        RightScale::MessageEncoder.for_agent('rs-instance-1-1').decode(output).to_json.should == @bundle.to_json
      ensure
        (File.delete(mock_output) if File.file?(mock_output)) rescue nil
      end
    end

  end

end
