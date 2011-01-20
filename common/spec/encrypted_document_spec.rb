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

describe RightScale::EncryptedDocument do
  
  include RightScale::SpecHelpers

  before(:all) do
    @test_data = "Test Data to Sign"
    @cert, @key = issue_cert
    @doc = RightScale::EncryptedDocument.new(@test_data, @cert)
  end

  it 'should create encrypted data' do
    @doc.encrypted_data.should_not be_nil
  end

  it 'should create encrypted data using either PEM or DER format' do
    @doc.encrypted_data(:pem).should_not be_nil
    @doc.encrypted_data(:der).should_not be_nil
  end

  it 'should decrypt correctly' do
    @doc.decrypted_data(@key, @cert).should == @test_data
  end

  it 'should load correctly with data in either PEM or DER format' do
    @doc = RightScale::EncryptedDocument.from_data(@doc.encrypted_data(:pem))
    @doc.decrypted_data(@key, @cert).should == @test_data
    @doc = RightScale::EncryptedDocument.from_data(@doc.encrypted_data(:der))
    @doc.decrypted_data(@key, @cert).should == @test_data
  end

end
