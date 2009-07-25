require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'right_link_tracer'
require 'right_link_log'

# Test data
class TestData
  def trace_me
    'I got traced!'
  end
end
class TestData2
  def self.trace_me_too
    'So did I!'
  end
end
module Traced
  class TestData3
    def trace_me_three
      'and me!'
    end
    def self.trace_me_four
      'and me and me!'
    end
  end
end
class TestData4
  def send_result
    'result'
  end
end
class TestData5
  def use_block
    yield
  end
end
class TestData6
  def do_not_fail?
    true
  end
  def [](index)
    index
  end
  def []=(index, value)
    index
  end
end

describe RightScale::RightLinkTracer do

  before(:all) do
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
    @test = TestData.new
    @test2 = TestData2.new
    @test3 = Traced::TestData3.new
    @test4 = TestData4.new
    @test5 = TestData5.new
    @test6 = TestData6.new
  end

  it 'should trace instance methods' do
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
    RightScale::RightLinkTracer.add_tracing_to_class(@test.class)
    @test.trace_me
  end

  it 'should trace class methods' do
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
    RightScale::RightLinkTracer.add_tracing_to_class(@test2.class)
    TestData2.trace_me_too
  end

  it 'should trace entire modules' do
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
    RightScale::RightLinkTracer.add_tracing_to_namespaces('Traced')
    @test3.trace_me_three
    Traced::TestData3.trace_me_four
  end

  it 'should return correct results' do
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
    RightScale::RightLinkTracer.add_tracing_to_class(@test4.class)
    @test4.send_result.should == 'result'
  end

  it 'should trace methods taking blocks' do
    RightScale::RightLinkLog.logger.should_receive(:debug).any_number_of_times
    RightScale::RightLinkTracer.add_tracing_to_class(@test5.class)
    @test5.use_block { 'result' }.should == 'result'    
  end

  it 'should handle methods names ending with special characters' do
    RightScale::RightLinkTracer.add_tracing_to_class(@test6.class)
  end

end