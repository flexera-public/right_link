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

describe RightScale::OperationResult do

  describe "when fetching results" do

    before do
      @success1 = RightScale::OperationResult.success(1)
      @success2 = RightScale::OperationResult.success(2)
      @simple_result = RightScale::Result.new("token", "to", @success1, "from")
      @hash = {"from1" => @success1, "from2" => @success2}
      @hash_result = RightScale::Result.new("token", "to", @hash, "from")
      @nil_result = RightScale::Result.new("token", "to", nil, "from")
      @error_result = RightScale::Result.new("token", "to", RightScale::OperationResult.error("Error"), "from")
    end

    it "should handle results hash and return only first value as an OperationResult" do
      result = RightScale::OperationResult.from_results(@hash)
      result.kind_of?(RightScale::OperationResult).should be_true
      result.status_code.should == RightScale::OperationResult::SUCCESS
      result.content.should == 1
    end

    it "should handle individual result and return it as an OperationResult" do
      result = RightScale::OperationResult.from_results(@simple_result)
      result.kind_of?(RightScale::OperationResult).should be_true
      result.status_code.should == RightScale::OperationResult::SUCCESS
      result.content.should == 1
    end

    it "should handle non-success result and return it as an OperationResult" do
      result = RightScale::OperationResult.from_results(@error_result)
      result.kind_of?(RightScale::OperationResult).should be_true
      result.status_code.should == RightScale::OperationResult::ERROR
      result.content.should == "Error"
    end

    it "should return error OperationResult if results is nil" do
      result = RightScale::OperationResult.from_results(nil)
      result.kind_of?(RightScale::OperationResult).should be_true
      result.status_code.should == RightScale::OperationResult::ERROR
      result.content.should == "No results"
    end

    it "should return error OperationResult if the results value is not recognized" do
      result = RightScale::OperationResult.from_results(0)
      result.kind_of?(RightScale::OperationResult).should be_true
      result.status_code.should == RightScale::OperationResult::ERROR
      result.content.should == "Invalid operation result type: 0"
    end
  end
  
  describe "when handling each type of result" do

    it "should store success content value and respond to success query" do
      result = RightScale::OperationResult.success({})
      result.kind_of?(RightScale::OperationResult).should be_true
      result.success?.should be_true
      result.error?.should be_false
      result.continue?.should be_false
      result.retry?.should be_false
      result.non_delivery?.should be_false
      result.content.should == {}
    end

    it "should treat non-delivery as error" do
      RightScale::OperationResult.non_delivery(0).error?.should be_true
    end

    it "should store error content value and respond to error query" do
      result = RightScale::OperationResult.error("Error")
      result.kind_of?(RightScale::OperationResult).should be_true
      result.error?.should be_true
      result.content.should == "Error"
    end

    it 'should store additional error string when given' do
      result = RightScale::OperationResult.error("Error", "details")
      result.kind_of?(RightScale::OperationResult).should be_true
      result.error?.should be_true
      result.content.should == "Error (details)"
    end

    it "should store exception info in error content value when given" do
      begin
        nil + "string"
      rescue Exception => e
        result = RightScale::OperationResult.error("Error", e)
      end
      result.kind_of?(RightScale::OperationResult).should be_true
      result.error?.should be_true
      (result.content =~ /Error \(NoMethodError: undefined method \`\+' for nil:NilClass in .*operation_result_spec.*\)$/).should be_true
    end

    it "should store continue content value and respond to continue query" do
      result = RightScale::OperationResult.continue("Continue")
      result.kind_of?(RightScale::OperationResult).should be_true
      result.continue?.should be_true
      result.content.should == "Continue"
    end

    it "should store retry content value and respond to retry query" do
      result = RightScale::OperationResult.retry("Retry")
      result.kind_of?(RightScale::OperationResult).should be_true
      result.retry?.should be_true
      result.content.should == "Retry"
    end

    it "should store multicast targets" do
      result = RightScale::OperationResult.multicast(["target"])
      result.kind_of?(RightScale::OperationResult).should be_true
      result.content.should == ["target"]
    end

    it "should store non-delivery content value and respond to non-delivery query" do
      result = RightScale::OperationResult.non_delivery("Non-delivery")
      result.kind_of?(RightScale::OperationResult).should be_true
      result.non_delivery?.should be_true
      result.content.should == "Non-delivery"
    end
  end

  describe "when converting result to string" do

    it "should display error message" do
      result = RightScale::OperationResult.error("some problem")
      result.to_s.should == "error (some problem)"
    end

    it "should convert error content to string if necessary" do
      result = RightScale::OperationResult.error({"data" => "some data", "message" => "some problem"})
      result.to_s.should == "error ({\"data\"=>\"some data\", \"message\"=>\"some problem\"})"
    end

    it "should truncate error message if too long" do
      result = RightScale::OperationResult.error("123456789012345678901234567890123456789012345678901234567890")
      result.to_s.should == "error (123456789012345678901234567890123456789012345678901234567...)"
      result.status.should == "error"
    end

    it "should display non-delivery reason" do
      result = RightScale::OperationResult.non_delivery(RightScale::OperationResult::TTL_EXPIRATION)
      result.to_s.should == "non-delivery (TTL expiration)"
      result.status.should == "non-delivery"
    end

  end

end
