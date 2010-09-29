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

module RightScale
  
  # Add the ability to compare tag updates for test purposes
  class TagUpdate
    def ==(other)
      @new_tags == other.new_tags && @obsolete_tags == other.obsolete_tags && @identity == other.identity
    end
  end
  
end

describe RightScale::SecureSerializer do
  
  include RightScale::SpecHelpers

  before(:all) do
    @certificate, @key = issue_cert
    @store = RightScale::StaticCertificateStore.new(@certificate, @certificate)
    @identity = "id"
    @data = RightScale::TagUpdate.new("identity", ["new tag"], ["obsolete tag"])
  end
  
  it 'should raise when not initialized' do
    lambda { RightScale::SecureSerializer.dump(@data) }.should raise_error
  end

  it 'should deserialize signed data' do
    RightScale::SecureSerializer.init(@identity, @certificate, @key, @store, false)
    data = RightScale::SecureSerializer.dump(@data)
    RightScale::SecureSerializer.load(data).should == @data
  end
  
  it 'should deserialize encrypted data' do
    RightScale::SecureSerializer.init(@identity, @certificate, @key, @store, true)
    data = RightScale::SecureSerializer.dump(@data)
    RightScale::SecureSerializer.load(data).should == @data
  end

end
