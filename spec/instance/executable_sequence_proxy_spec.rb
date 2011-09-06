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

  before(:each) do
    setup_state
    @audit = flexmock('audit')
    @context = flexmock('context', :audit => @audit, :payload => { :p => 'payload' })
    @context.should_receive(:succeeded=)
    @audit.should_receive(:update_status)
    flexmock(RightScale::AuditProxy).should_receive(:new).and_return(@audit)
    @proxy = RightScale::ExecutableSequenceProxy.new(@context)
  end

  after(:each) do
    cleanup_state
  end

  def run_em_test(&block)
    last_exception = nil
    EM.threadpool_size = 1
    EM.run do
      EM.add_timer(5) { EM.stop; raise 'Timeout' }
      EM.defer do
        begin
          block.call
          EM.stop
        rescue Exception => e
          last_exception = e
          EM.stop
        end
      end
    end

    # reraise with full backtrace for debugging purposes. this assumes the
    # exception class accepts a single string on construction.
    if last_exception
      message = "#{last_exception.message}\n#{last_exception.backtrace.join("\n")}"
      if last_exception.class == ArgumentError
        raise ArgumentError, message
      else
        begin
          raise last_exception.class, message
        rescue ArgumentError
          # exception class does not support single string construction.
          message = "#{last_exception.class}: #{message}"
          raise message
        end
      end
    end
  end

  it 'should run a valid command' do
    status = flexmock('status', :success? => true)
    flexmock(RightScale).should_receive(:popen3).and_return do |o|
      o[:target].instance_variable_set(:@audit_closed, true)
      o[:target].send(o[:exit_handler], status)
    end
    @proxy.instance_variable_get(:@deferred_status).should == nil
    run_em_test { @proxy.run }
    @proxy.instance_variable_get(:@deferred_status).should == :succeeded
  end

  it 'should find the cook utility' do
    status = flexmock('status', :success? => true)
    cmd = nil
    flexmock(RightScale).should_receive(:popen3).and_return do |o|
      cmd = o[:command] 
      o[:target].instance_variable_set(:@audit_closed, true)
      o[:target].send(o[:exit_handler], status)
    end
    run_em_test { @proxy.run }

    # note that normalize_path makes it tricky to guess at full command string
    # so it is best to rely on config constants.
    cook_util_path = File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'cook_runner.rb'))
    expected = "#{File.basename(RightScale::AgentConfig.sandbox_ruby_cmd)} \"#{cook_util_path}\""
    if RightScale::Platform.windows?
      matcher = Regexp.compile(".*" + Regexp.escape(" /C type ") + ".*" + Regexp.escape("rs_executable_sequence.txt | ") + ".*" + Regexp.escape(expected))
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
    run_em_test { @proxy.run }
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
      begin
        output = File.read(mock_output)
        output.should == "#{JSON.dump(@context.payload)}\n"
      ensure
        (File.delete(mock_output) if File.file?(mock_output)) rescue nil
      end
    end

  end

end
