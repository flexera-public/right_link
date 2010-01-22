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

describe RightScale::RsaKeyPair do

  before(:all) do
    @pair = RightScale::RsaKeyPair.new
  end

  it 'should create a private and a public keys' do
    @pair.has_private?.should be_true
  end

  it 'should strip out private key in to_public' do
    @pair.to_public.has_private?.should be_false
  end

  it 'should save' do
    filename = File.join(File.dirname(__FILE__), "key.pem")
    @pair.save(filename)
    File.size(filename).should be > 0
    File.delete(filename)
  end

  it 'should load' do
    filename = File.join(File.dirname(__FILE__), "key.pem")
    @pair.save(filename)
    key = RightScale::RsaKeyPair.load(filename)
    File.delete(filename)
    key.should_not be_nil
    key.data.should == @pair.data
  end

end