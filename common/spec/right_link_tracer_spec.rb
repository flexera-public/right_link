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
    @test = TestData.new
    @test2 = TestData2.new
    @test3 = Traced::TestData3.new
    @test4 = TestData4.new
    @test5 = TestData5.new
    @test6 = TestData6.new
  end

  it 'should trace instance methods' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).twice
    RightScale::RightLinkTracer.add_tracing_to_class(@test.class)
    @test.trace_me
  end

  it 'should trace class methods' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).twice
    RightScale::RightLinkTracer.add_tracing_to_class(@test2.class)
    TestData2.trace_me_too
  end

  it 'should trace entire modules' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).times(4)
    RightScale::RightLinkTracer.add_tracing_to_namespaces('Traced')
    @test3.trace_me_three
    Traced::TestData3.trace_me_four
  end

  it 'should return correct results' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).twice
    RightScale::RightLinkTracer.add_tracing_to_class(@test4.class)
    @test4.send_result.should == 'result'
  end

  it 'should trace methods taking blocks' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).twice
    RightScale::RightLinkTracer.add_tracing_to_class(@test5.class)
    @test5.use_block { 'result' }.should == 'result'    
  end

  it 'should handle methods names ending with special characters' do
    RightScale::RightLinkTracer.add_tracing_to_class(@test6.class)
  end

end