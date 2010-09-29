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

describe RightScale::MulticastReceiver do

  describe "when handling a result" do

    before do
      @timer = flexmock("timer", :cancel => true).by_default
      flexmock(RightScale::RightLinkLog).should_receive(:info).never.by_default
      flexmock(RightScale::RightLinkLog).should_receive(:error).never.by_default
      @multicast = RightScale::OperationResult.multicast(["rs-from1", "rs-from2", "shared"])
      @multicast_empty = RightScale::OperationResult.multicast([])
      @multicast_result = RightScale::Result.new("token", "to", @multicast, "mapper")
      @multicast_empty_result = RightScale::Result.new("token", "to", @multicast_empty, "mapper")
      @success = RightScale::OperationResult.success("success")
      @success_result1 = RightScale::Result.new("token", "to", @success, "rs-from1")
      @success_result2 = RightScale::Result.new("token", "to", @success, "rs-from2")
      @success_result3 = RightScale::Result.new("token", "to", @success, "shared")
      @error = RightScale::OperationResult.error("Error")
      @error_result = RightScale::Result.new("token", "to", @error, "rs-from1")
      @each_count = 0
      @each_blk = lambda do |token, from, content|
        @each_token = token; @each_from = from; @each_content = content; @each_count += 1
      end
      @done_count = 0
      @done_blk = lambda do |token, to, from, timed_out|
        @done_token = token; @done_to = to; @done_from = from; @done_timed_out = timed_out; @done_count += 1
      end
      @receiver = RightScale::MulticastReceiver.new("test", @done_blk, @each_blk)
    end

    it "should handle multicast first as first in sequence and record the to list" do
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @receiver.handle(@multicast_result)
      @receiver.instance_variable_get(:@to).should == ["rs-from1", "rs-from2", "shared"]
    end

    it "should handle result following initial multicast result and record the from" do
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @receiver.handle(@multicast_result)
      @receiver.handle(@success_result2)
      @receiver.instance_variable_get(:@from).should == ["rs-from2"]
    end

    it "should set timer if there are one or more multicast targets" do
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).once
      @receiver.handle(@multicast_result)
    end

    it "should not set timer if there are no multicast targets" do
      flexmock(RightScale::RightLinkLog).should_receive(:info)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).never
      @receiver.handle(@multicast_empty_result)
    end

    it "should log an info message if the multicast targets list is empty" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with("No targets found to test")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @receiver.handle(@multicast_empty_result)
    end

    it "should not set timer if the timeout is nil" do
      flexmock(RightScale::RightLinkLog).should_receive(:info)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).never
      @receiver = RightScale::MulticastReceiver.new("test", @done_blk, @each_blk, nil)
      @receiver.handle(@multicast_empty_result)
    end

    it "should call each block after each individual multicast result that is a success" do
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @receiver.handle(@multicast_result)
      @receiver.handle(@success_result2)
      @each_count.should == 1
      @receiver.instance_variable_get(:@from).should == ["rs-from2"]
      @receiver.handle(@success_result3)
      @each_count.should == 2
      @receiver.instance_variable_get(:@from).should == ["rs-from2", "shared"]
      @receiver.handle(@success_result1)
      @each_count.should == 3
      @receiver.instance_variable_get(:@from).should == ["rs-from2", "shared", "rs-from1"]
    end

    it "should call done block after all individual multicast results are received and cancel timer" do
      @timer.should_receive(:cancel).once
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @receiver.handle(@multicast_result)
      @receiver.handle(@success_result2)
      @done_count.should == 0
      @receiver.instance_variable_get(:@from).should == ["rs-from2"]
      @receiver.handle(@success_result3)
      @done_count.should == 0
      @receiver.instance_variable_get(:@from).should == ["rs-from2", "shared"]
      @receiver.handle(@success_result1)
      @done_count.should == 1
      @receiver.instance_variable_get(:@from).should == ["rs-from2", "shared", "rs-from1"]
    end

    it "should call done block if timeout before all individual multicast results are received" do
      EM.run do
        @receiver = RightScale::MulticastReceiver.new("test", @done_blk, @each_blk, 0.1)
        @receiver.handle(@multicast_result)
        @receiver.handle(@success_result2)
        @done_count.should == 0
        @receiver.instance_variable_get(:@from).should == ["rs-from2"]
        @receiver.handle(@success_result3)
        @done_count.should == 0
        EM.add_timer(0.2) do
          @done_count.should == 1
          @done_token.should == "token"
          @done_to.should == ["rs-from1", "rs-from2", "shared"]
          @done_from.should == ["rs-from2", "shared"]
          @done_timed_out.should be_true
          EM.stop
        end
      end
    end

    it "should call each and done blocks for result if there was no initial multicast result" do
      @receiver.handle(@success_result2)
      @receiver.instance_variable_get(:@from).should == ["rs-from2"]
      @each_count.should == 1
      @each_token.should == "token"
      @each_from.should == "rs-from2"
      @each_content.should == "success"
      @done_count.should == 1
      @done_token.should == "token"
      @done_to.should == ["rs-from2"]
      @done_from.should == ["rs-from2"]
      @done_timed_out.should be_false
    end

    it "should log error result and not call the each block" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with("Failed to test on target rs-from1: Error").once
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @receiver.handle(@multicast_result)
      @receiver.handle(@error_result)
      @each_count.should == 0
    end

    it "should log exception resulting from done block execution" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with("Failed to complete test: Error").once
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @done_blk = lambda { |_, _, _, _| raise Exception, "Error" }
      @receiver = RightScale::MulticastReceiver.new("test", @done_blk)
      @receiver.handle(@success_result1)
    end

    it "should continue with done block even if and each block fails on last result" do
      flexmock(RightScale::RightLinkLog).should_receive(:error).with("Failed to handle test for one target: Error").times(3)
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @each_blk = lambda { |_, _, _| raise Exception, "Error" }
      @receiver = RightScale::MulticastReceiver.new("test", @done_blk, @each_blk)
      @receiver.handle(@multicast_result)
      @receiver.handle(@success_result2)
      @receiver.handle(@success_result3)
      @receiver.handle(@success_result1)
      @done_count.should == 1
      @done_to.should == ["rs-from1", "rs-from2", "shared"]
      @done_from.should == ["rs-from2", "shared", "rs-from1"]
    end
  end

end
