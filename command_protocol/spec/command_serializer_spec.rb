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

describe RightScale::CommandSerializer do

  before(:all) do
    @sample_data = [ 42, 'fourty two', { :haha => 42, 'hoho' => 'fourty_two' }]
  end

  it 'should serialize' do
    @sample_data.each do |data|
      RightScale::CommandSerializer.dump(data)
    end
  end

  it 'should deserialize' do
    @sample_data.each do |data|
      RightScale::CommandSerializer.load(RightScale::CommandSerializer.dump(data)).should == data
    end
  end

  it 'should add separators' do
    serialized = ''
    @sample_data.each do |data|
      serialized << RightScale::CommandSerializer.dump(data)
    end
    serialized.split(RightScale::CommandSerializer::SEPARATOR).size.should == @sample_data.size
  end

end
