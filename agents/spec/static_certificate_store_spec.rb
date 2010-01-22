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

describe RightScale::StaticCertificateStore do
  
  include RightScale::SpecHelpers

  before(:all) do
    @signer, key = issue_cert
    @recipient, key = issue_cert
    @cert, @key = issue_cert
    @store = RightScale::StaticCertificateStore.new(@signer, @recipient)
  end

  it 'should not raise when passed nil objects' do
    res = nil
    lambda { res = @store.get_signer(nil) }.should_not raise_error
    res.should == [ @signer ]
    lambda { res = @store.get_recipients(nil) }.should_not raise_error
    res.should == [ @recipient ]
  end

  it 'should return signer certificates' do
    @store.get_signer('anything').should == [ @signer ]
  end

  it 'should return recipient certificates' do
    @store.get_recipients('anything').should == [ @recipient ]
  end
  
end