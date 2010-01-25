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

describe RightScale::CertificateCache do

  before(:each) do
    @cache = RightScale::CertificateCache.new(2)
  end

  it 'should allow storing and retrieving objects' do
    @cache['some_id'].should be_nil
    @cache['some_id'] = 'some_value'
    @cache['some_id'].should == 'some_value'
  end

  it 'should not store more than required' do
    @cache[1] = 'oldest'
    @cache[2] = 'older'
    @cache[1].should == 'oldest'
    @cache[2].should == 'older'
  
    @cache[3] = 'new'
    @cache[3].should == 'new'

    @cache[1].should be_nil
    @cache[2].should == 'older'
  end

  it 'should use LRU to remove entries' do
    @cache[1] = 'oldest'
    @cache[2] = 'older'
    @cache[1].should == 'oldest'
    @cache[2].should == 'older'
  
    @cache[1] = 'new'
    @cache[3] = 'newer'
    @cache[1].should == 'new'
    @cache[3].should == 'newer'

    @cache[2].should be_nil
  end

  it 'should store items returned by block' do
    @cache[1].should be_nil
    item = @cache.get(1) { 'item' }
    item.should == 'item'
    @cache[1].should == 'item'
  end

end