#
# Copyright (c) 2010-2011 RightScale Inc
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

describe RightScale::BundlesQueue do

  include RightScale::SpecHelper

  it_should_behave_like 'mocks shutdown request'

  before(:each) do
    @term = false
    @queue = RightScale::BundlesQueue.new { @term = true; EM.stop }
    @audit = flexmock('audit')
    @audit.should_receive(:update_status).and_return(true)
    @bundle = flexmock('bundle', :thread_name => 'some thread name')
    @bundle.should_receive(:to_json).and_return("[\"some json\"]")
    @context = flexmock('context', :audit => @audit, :payload => @bundle, :decommission => false, :succeeded => true)
    @callback = nil
    @sequence = flexmock('sequence', :context => @context)
    @sequence.should_receive(:callback).and_return { |callback| @callback = callback; true }
    @sequence.should_receive(:errback).and_return(true)
    @sequence.should_receive(:run).and_return { @status = :run; @callback.call }
    flexmock(@queue).should_receive(:create_sequence).and_return { @sequence }
    flexmock(::RightScale::Log).should_receive(:error).never
  end

  it 'should default to non active' do
    @queue.push(@context)
    @status.should be_nil
  end

  it 'should run bundles once active' do
    @queue.activate
    run_em_test do
      @queue.push(@context)
      @queue.close
    end
    @status.should == :run
    @term.should be_true
  end

  it 'should not be active after being closed' do
    @queue.activate
    run_em_test do
      @queue.close
      @queue.push(@context)
    end
    @status.should be_nil
    @term.should be_true
  end

  it 'should process the shutdown bundle' do
    processed = false
    flexmock(@mock_shutdown_request).
      should_receive(:process).
      and_return do
        @queue.push(@context)
        @queue.close
        processed = true
        true
      end
    @queue.activate
    run_em_test do
      @queue.push(::RightScale::BundlesQueue::SHUTDOWN_BUNDLE)
    end
    processed.should be_true
    @term.should be_true
  end

end
