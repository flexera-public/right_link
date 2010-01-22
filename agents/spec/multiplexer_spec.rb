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

require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'multiplexer'

describe RightScale::Multiplexer do

  before(:all) do
    @target1 = flexmock('Target 1')
    @target2 = flexmock('Target 2')
    @target3 = flexmock('Target 3')
    @multiplexer = RightScale::Multiplexer.new(@target1, @target2, @target3)
  end

  it 'should multiplex' do
    @target1.should_receive(:some_method).once.with('arg', 'arg2')
    @target2.should_receive(:some_method).once.with('arg', 'arg2')
    @target3.should_receive(:some_method).once.with('arg', 'arg2')
    @multiplexer.some_method('arg', 'arg2')
  end

  it 'should retrieve the first result' do
    @target1.should_receive(:some_method).once.with('arg', 'arg2').and_return('res1')
    @target2.should_receive(:some_method).once.with('arg', 'arg2').and_return('res2')
    @target3.should_receive(:some_method).once.with('arg', 'arg2').and_return('res3')
    @multiplexer.some_method('arg', 'arg2').should == 'res1'
  end

end
