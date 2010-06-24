#
# Copyright (c) 2009 RightScale Inc
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

  include RightScale::SpecHelpers

  before(:each) do
    setup_state
    @bundle = flexmock('bundle')
    @bundle.should_receive(:audit_id).and_return(42)
    @auditor = flexmock('auditor')
    @auditor.should_receive(:update_status)
    flexmock(RightScale::AuditorProxy).should_receive(:instance).and_return(@auditor)
    @proxy = RightScale::ExecutableSequenceProxy.new(@bundle)
  end

  after(:each) do
    cleanup_state
  end

  it 'should run a valid command' do
    status = flexmock('status', :success? => true)
    flexmock(RightScale).should_receive(:popen3).and_return { |o| o[:target].send(o[:exit_handler], status) }
    @proxy.instance_variable_get(:@deferred_status).should == nil
    @proxy.run 
    @proxy.instance_variable_get(:@deferred_status).should == :succeeded
  end

  it 'should find the cook utility' do
    status = flexmock('status', :success? => true)
    cmd = nil
    flexmock(RightScale).should_receive(:popen3).and_return do |o|
      cmd = o[:command] 
      o[:target].send(o[:exit_handler], status)
    end
    @proxy.run

    # note that normalize_path makes it tricky to guess at full command string
    # so it is best to rely on config constants.
    cook_util_path = File.join(RightScale::RightLinkConfig[:right_link_path], 'scripts', 'lib', 'cook.rb')
    expected = "#{RightScale::RightLinkConfig[:sandbox_ruby_cmd]} \"#{cook_util_path}\""
    cmd.should == expected
  end

  it 'should report failures when cook fails' do
    status = flexmock('status', :success? => false, :exitstatus => 1)
    flexmock(RightScale).should_receive(:popen3).and_return { |o| o[:target].send(o[:exit_handler], status) }
    @auditor.should_receive(:append_error).twice
    @proxy.instance_variable_get(:@deferred_status).should == nil
    @proxy.run 
    @proxy.instance_variable_get(:@deferred_status).should == :failed
  end

  it 'should report failures when cook outputs errors' do
    status = flexmock('status', :success? => false, :exitstatus => 1)
    flexmock(RightScale).should_receive(:popen3).and_return do |o| 
      o[:target].send(o[:stderr_handler], 'blarg')
      o[:target].send(o[:exit_handler], status)
    end
    @auditor.should_receive(:append_error).twice.with('blarg', Hash)
    @proxy.instance_variable_get(:@deferred_status).should == nil
    @proxy.run 
    @proxy.instance_variable_get(:@deferred_status).should == :failed
  end

  it 'should report failures title and message from cook error outputs' do
    status = flexmock('status', :success? => false, :exitstatus => 1)
    flexmock(RightScale).should_receive(:popen3).and_return do |o| 
      o[:target].send(o[:stderr_handler], "title\nmessage\nmessage_line2")
      o[:target].send(o[:exit_handler], status)
    end
    @auditor.should_receive(:append_error).once.with('title', Hash)
    @auditor.should_receive(:append_error).once.with("message\nmessage_line2", :audit_id => 42)
    @proxy.instance_variable_get(:@deferred_status).should == nil
    @proxy.run 
    @proxy.instance_variable_get(:@deferred_status).should == :failed
  end

  context 'when running popen3' do

    it 'should call the cook utility' do
      mock_output = File.join(File.dirname(__FILE__), 'cook_mock_output')
      File.delete(mock_output) if File.exists?(mock_output)
      flexmock(@proxy).should_receive(:cook_path).and_return(File.join(File.dirname(__FILE__), 'cook_mock.rb'))
      flexmock(@proxy).should_receive(:succeed).and_return { |*args| EM.stop }
      flexmock(@proxy).should_receive(:report_failure).and_return { |*args| puts args.inspect; EM.stop }
      EM.run do
        EM.add_timer(5) { EM.stop; raise 'Timeout' }
        EM.defer { @proxy.run }
      end
      begin
        output = File.read(mock_output)
        output.should == "#{JSON.dump(@bundle)}\n"
      ensure
        (File.delete(mock_output) if File.file?(mock_output)) rescue nil
      end
    end

  end

end
