#
# Copyright (c) 2010 RightScale Inc
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

module RightScale
  module BundlesQueueSpec
    class ShutdownManager

      def initialize
        @shutdown_request = RightScale::ShutdownManagement::ShutdownRequest.new
      end

      def shutdown_request; return @shutdown_request; end
      def manage_shutdown_request; yield if block_given?; end

    end
  end
end

describe RightScale::BundlesQueue do

  before(:each) do
    @term = false
    @shutdown_manager = RightScale::BundlesQueueSpec::ShutdownManager.new
    @queue = RightScale::BundlesQueue.new(@shutdown_manager) { @term = true; EM.stop }
    @context = flexmock('context', :audit => 42, :decommission => false)
    flexmock(RightScale::ExecutableSequenceProxy).new_instances.should_receive(:run).and_return { @status = :run; EM.stop }
  end
 
  it 'should default to non active' do
    @queue.push(@context)
    @status.should be_nil
  end

  it 'should run bundles once active' do
    @queue.activate
    EM.run do
      EM.add_timer(5) { EM.stop }
      @queue.push(@context)
    end
    @status.should == :run
  end

  it 'should not be active after being closed' do
    @queue.activate
    EM.run do 
      EM.add_timer(5) { EM.stop }
      @queue.close
      @queue.push(@context)
    end
    @status.should be_nil
  end

  it 'should call back continuation on close' do
    EM.run do
      EM.add_timer(5) { EM.stop }
      @queue.activate
      @term.should be_false
      @queue.close
    end
    @term.should be_true
  end

end
