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

  # Add the ability to compare results for test purposes
  class Result
    def ==(other)
      @token == other.token && @to == other.to && @from == other.from && @results == other.results
    end
  end

end

describe RightScale::SecureSerializer do
  
  include RightScale::SpecHelpers

  before(:all) do
    @certificate, @key = issue_cert
    @store = RightScale::StaticCertificateStore.new(@certificate, @certificate)
    @identity = "id"
  end

  it 'should raise when not initialized' do
    data = RightScale::Result.new("token", "to", "from", ["results"])
    lambda { RightScale::SecureSerializer.dump(data) }.should raise_error
  end

  it 'should raise when data not serialized with MessagePack or JSON' do
    data = RightScale::Result.new("token", "to", "from", ["results"])
    RightScale::SecureSerializer.init(RightScale::Serializer.new, @identity, @certificate, @key, @store, false)
    lambda { RightScale::SecureSerializer.load(Marshal.dump(data)) }.should raise_error(RightScale::Serializer::SerializationError)
    lambda { RightScale::SecureSerializer.load(YAML.dump(data)) }.should raise_error(RightScale::Serializer::SerializationError)
  end

  describe "using MessagePack" do

    before(:each) do
      flexmock(JSON).should_receive(:dump).never
      flexmock(JSON).should_receive(:load).never
      @data = RightScale::Result.new("token", "to", "from", ["results"], nil, nil, nil, nil, [12, 12])
    end

    it 'should unserialize signed data' do
      RightScale::SecureSerializer.init(RightScale::Serializer.new, @identity, @certificate, @key, @store, false)
      data = RightScale::SecureSerializer.dump(@data)
      RightScale::SecureSerializer.load(data).should == @data
    end

    it 'should unserialize encrypted data' do
      RightScale::SecureSerializer.init(RightScale::Serializer.new, @identity, @certificate, @key, @store, true)
      data = RightScale::SecureSerializer.dump(@data)
      RightScale::SecureSerializer.load(data).should == @data
    end

  end

  describe "using JSON" do

    before(:each) do
      flexmock(MessagePack).should_receive(:dump).never
      flexmock(MessagePack).should_receive(:load).never
      @data = RightScale::Result.new("token", "to", "from", ["results"], nil, nil, nil, nil, [11, 11])
    end

    it 'should unserialize signed data' do
      RightScale::SecureSerializer.init(RightScale::Serializer.new, @identity, @certificate, @key, @store, false)
      data = RightScale::SecureSerializer.dump(@data)
      RightScale::SecureSerializer.load(data).should == @data
    end

    it 'should unserialize encrypted data' do
      RightScale::SecureSerializer.init(RightScale::Serializer.new, @identity, @certificate, @key, @store, true)
      data = RightScale::SecureSerializer.dump(@data)
      RightScale::SecureSerializer.load(data).should == @data
    end

  end

end
