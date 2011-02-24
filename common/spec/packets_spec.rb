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
require File.join(File.dirname(__FILE__), '..', 'lib', 'common', 'serializer')

class TestPacket < RightScale::Packet
  @@cls_attr = "ignore"
  def initialize(attr1, duration = nil, size = nil)
    @attr1 = attr1
    @duration = duration
    @size = size
    @version = [RightScale::Packet::VERSION, RightScale::Packet::VERSION]
  end
end

describe "Packet: Base class" do

  it "should be an abstract class" do
    lambda { RightScale::Packet.new }.should raise_error(NotImplementedError, "RightScale::Packet is an abstract class.")
  end

  it "should retrieve version" do
    packet = TestPacket.new(1)
    packet.recv_version.should == RightScale::Packet::VERSION
    packet.send_version.should == RightScale::Packet::VERSION
  end

  it "should store version" do
    packet = TestPacket.new(1)
    packet.send_version.should == RightScale::Packet::VERSION
    packet.send_version = 5
    packet.send_version.should == 5
    lambda { packet.recv_version = 5 }.should raise_error
  end

  it "should convert to string with packet name in lower snake case" do
    packet = TestPacket.new(1)
    packet.name.should == "test_packet"
    packet.to_s.should == "[test_packet]"
  end

  it "should convert to string including version if requested" do
    packet = TestPacket.new(1)
    packet.send_version = 5
    packet.to_s(filter = nil, version = :recv_version).should == "[test_packet v#{RightScale::Packet::VERSION}]"
    packet.to_s(filter = nil, version = :send_version).should == "[test_packet v5]"
  end

  it "should convert to string including duration if filtered and size is also known" do
    packet = TestPacket.new(1, 0.042122, 323)
    packet.to_s(filter = nil).should == "[test_packet] (323 bytes, 0.042 sec)"
    packet.to_s(filter = []).should == "[test_packet] (323 bytes)"
    packet.to_s(filter = [:duration]).should == "[test_packet] (323 bytes, 0.042 sec)"
    packet = TestPacket.new(1, 0.042122)
    packet.to_s(filter = [:duration]).should == "[test_packet]"
  end

  it "should convert floating point values to decimal digit string with at least two digit precision" do
    packet = TestPacket.new(1)
    packet.enough_precision(100.5).should == "101"
    packet.enough_precision(100.4).should == "100"
    packet.enough_precision(99.0).should == "99"
    packet.enough_precision(10.5).should == "11"
    packet.enough_precision(10.4).should == "10"
    packet.enough_precision(9.15).should == "9.2"
    packet.enough_precision(9.1).should == "9.1"
    packet.enough_precision(1.05).should == "1.1"
    packet.enough_precision(1.01).should == "1.0"
    packet.enough_precision(1.0).should == "1.0"
    packet.enough_precision(0.995).should == "1.00"
    packet.enough_precision(0.991).should == "0.99"
    packet.enough_precision(0.0995).should == "0.100"
    packet.enough_precision(0.0991).should == "0.099"
    packet.enough_precision(0.00995).should == "0.0100"
    packet.enough_precision(0.00991).should == "0.0099"
    packet.enough_precision(0.000995).should == "0.00100"
    packet.enough_precision(0.000991).should == "0.00099"
    packet.enough_precision(0.000005).should == "0.00001"
    packet.enough_precision(0.000001).should == "0.00000"
    packet.enough_precision(0.0).should == "0"
    packet.enough_precision(55).should == "55"
  end

  it "should be one-way by default" do
    TestPacket.new(1).one_way.should be_true
  end

  describe "using MessagePack" do
    it "should know how to dump itself to MessagePack" do
      packet = TestPacket.new(1)
      packet.should respond_to(:to_msgpack)
    end

    it "should dump the class name in 'msgpack_class' key" do
      packet = TestPacket.new(42)
      packet.to_msgpack.should =~ /msgpack_class.*TestPacket/
    end

    it "should dump instance variables in 'data' key" do
      packet = TestPacket.new(188)
      packet.to_msgpack.should =~ /data.*attr1/
    end

    it "should not dump class variables" do
      packet = TestPacket.new(382)
      packet.to_msgpack.should_not =~ /cls_attr/
    end

    it "should remove '@' from instance variables" do
      packet = TestPacket.new(2)
      packet.to_msgpack.should_not =~ /@attr1/
      packet.to_msgpack.should =~ /attr1/
    end
  end

  describe "using JSON" do
    it "should know how to dump itself to JSON" do
      packet = TestPacket.new(1)
      packet.should respond_to(:to_json)
    end

    it "should dump the class name in 'json_class' key" do
      packet = TestPacket.new(42)
      packet.to_json.should =~ /\"json_class\":\"TestPacket\"/
    end

    it "should dump instance variables in 'data' key" do
      packet = TestPacket.new(188, nil, 323)
      json = packet.to_json
      json.should =~ /\"data\":\{.*\"attr1\":188.*\}/
      json.should =~ /\"data\":\{.*\"duration\":null.*\}/
      json.should =~ /\"data\":\{.*\"size\":323.*\}/
      json.should =~ /\"data\":\{.*\"version\":\[\d*,\d*\].*\}/
    end

    it "should not dump class variables" do
      packet = TestPacket.new(382)
      packet.to_json.should_not =~ /cls_attr/
    end

    it "should remove '@' from instance variables" do
      packet = TestPacket.new(2)
      packet.to_json.should_not =~ /@attr1/
      packet.to_json.should =~ /attr1/
    end
  end
end


describe "Packet: Request" do
  it "should dump/load as MessagePack objects" do
    packet = RightScale::Request.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef',
                                     :reply_to => 'reply_to', :tries => ['try'])
    packet2 = MessagePack.load(packet.to_msgpack)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.scope.should == packet2.scope
    packet.token.should == packet2.token
    packet.reply_to.should == packet2.reply_to
    packet.tries.should == packet2.tries
    packet.expires_at.should == packet2.expires_at
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should dump/load as JSON objects" do
    packet = RightScale::Request.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef',
                                     :reply_to => 'reply_to', :tries => ['try'])
    packet2 = JSON.load(packet.to_json)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.scope.should == packet2.scope
    packet.token.should == packet2.token
    packet.reply_to.should == packet2.reply_to
    packet.tries.should == packet2.tries
    packet.expires_at.should == packet2.expires_at
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should default selector to :any" do
    packet = RightScale::Request.new('/some/foo', 'payload')
    packet.selector.should == :any
  end

  it "should convert selector from :least_loaded or :random to :any" do
    packet = RightScale::Request.new('/some/foo', 'payload', :selector => :least_loaded)
    packet.selector.should == :any
    packet = RightScale::Request.new('/some/foo', 'payload', :selector => "least_loaded")
    packet.selector.should == :any
    packet = RightScale::Request.new('/some/foo', 'payload', :selector => :random)
    packet.selector.should == :any
    packet = RightScale::Request.new('/some/foo', 'payload', :selector => "random")
    packet.selector.should == :any
    packet = RightScale::Request.new('/some/foo', 'payload', :selector => :any)
    packet.selector.should == :any
    packet = RightScale::Request.new('/some/foo', 'payload')
    packet.selector.should == :any
  end

  it "should distinguish fanout request" do
    RightScale::Request.new('/some/foo', 'payload').fanout?.should be_false
    RightScale::Request.new('/some/foo', 'payload', :selector => 'all').fanout?.should be_true
  end

  it "should convert created_at to expires_at" do
    packet = RightScale::Request.new('/some/foo', 'payload', :expires_at => 100000)
    packet2 = JSON.parse(packet.to_json.sub("expires_at", "created_at"))
    packet2.expires_at.should == 100900
    packet = RightScale::Request.new('/some/foo', 'payload', :expires_at => 0)
    packet2 = JSON.parse(packet.to_json.sub("expires_at", "created_at"))
    packet2.expires_at.should == 0
  end

  it "should not be one-way" do
    RightScale::Request.new('/some/foo', 'payload').one_way.should be_false
  end

  it "should use current version by default when constructing" do
    packet = RightScale::Request.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef',
                                     :reply_to => 'reply_to', :tries => ['try'])
    packet.recv_version.should == RightScale::Packet::VERSION
    packet.send_version.should == RightScale::Packet::VERSION
  end

  it "should use default version if none supplied when unmarshalling" do
    packet = RightScale::Request.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef',
                                     :reply_to => 'reply_to', :tries => ['try'])
    packet.instance_variable_set(:@version, nil)
    MessagePack.load(packet.to_msgpack).send_version.should == RightScale::Packet::DEFAULT_VERSION
    JSON.load(packet.to_json).send_version.should == RightScale::Packet::DEFAULT_VERSION
  end
end


describe "Packet: Push" do
  it "should dump/load as MessagePack objects" do
    packet = RightScale::Push.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :tries => ['try'])
    packet2 = MessagePack.load(packet.to_msgpack)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tries.should == packet2.tries
    packet.expires_at.should == packet2.expires_at
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should dump/load as JSON objects" do
    packet = RightScale::Push.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :tries => ['try'])
    packet2 = JSON.load(packet.to_json)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tries.should == packet2.tries
    packet.expires_at.should == packet2.expires_at
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should default selector to :any" do
    packet = RightScale::Push.new('/some/foo', 'payload')
    packet.selector.should == :any
  end

  it "should convert selector from :least_loaded or :random to :any" do
    packet = RightScale::Push.new('/some/foo', 'payload', :selector => :least_loaded)
    packet.selector.should == :any
    packet = RightScale::Push.new('/some/foo', 'payload', :selector => "least_loaded")
    packet.selector.should == :any
    packet = RightScale::Push.new('/some/foo', 'payload', :selector => :random)
    packet.selector.should == :any
    packet = RightScale::Push.new('/some/foo', 'payload', :selector => "random")
    packet.selector.should == :any
    packet = RightScale::Push.new('/some/foo', 'payload', :selector => :any)
    packet.selector.should == :any
  end

  it "should distinguish fanout request" do
    RightScale::Push.new('/some/foo', 'payload').fanout?.should be_false
    RightScale::Push.new('/some/foo', 'payload', :selector => 'all').fanout?.should be_true
  end

  it "should convert created_at to expires_at" do
    packet = RightScale::Push.new('/some/foo', 'payload', :expires_at => 100000)
    packet2 = JSON.parse(packet.to_json.sub("expires_at", "created_at"))
    packet2.expires_at.should == 100900
    packet = RightScale::Push.new('/some/foo', 'payload', :expires_at => 0)
    packet2 = JSON.parse(packet.to_json.sub("expires_at", "created_at"))
    packet2.expires_at.should == 0
  end

  it "should be one-way" do
    RightScale::Push.new('/some/foo', 'payload').one_way.should be_true
  end

  it "should use current version by default when constructing" do
    packet = RightScale::Push.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :tries => ['try'])
    packet.recv_version.should == RightScale::Packet::VERSION
    packet.send_version.should == RightScale::Packet::VERSION
  end

  it "should use default version if none supplied when unmarshalling" do
    packet = RightScale::Push.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :tries => ['try'])
    packet.instance_variable_set(:@version, nil)
    MessagePack.load(packet.to_msgpack).send_version.should == RightScale::Packet::DEFAULT_VERSION
    JSON.load(packet.to_json).send_version.should == RightScale::Packet::DEFAULT_VERSION
  end
end


describe "Packet: Result" do
  it "should dump/load as MessagePack objects" do
    packet = RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from', 'request_from', ['try'], true)
    packet2 = MessagePack.load(packet.to_msgpack)
    packet.token.should == packet2.token
    packet.to.should == packet2.to
    packet.results.should == packet2.results
    packet.from.should == packet2.from
    packet.request_from.should == packet2.request_from
    packet.tries.should == packet2.tries
    packet.persistent.should == packet2.persistent
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should dump/load as JSON objects" do
    packet = RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from', 'request_from', ['try'], true)
    packet2 = JSON.load(packet.to_json)
    packet.token.should == packet2.token
    packet.to.should == packet2.to
    packet.results.should == packet2.results
    packet.from.should == packet2.from
    packet.request_from.should == packet2.request_from
    packet.tries.should == packet2.tries
    packet.persistent.should == packet2.persistent
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should use current version by default when constructing" do
    packet = RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from', 'request_from', ['try'], true)
    packet.recv_version.should == RightScale::Packet::VERSION
    packet.send_version.should == RightScale::Packet::VERSION
  end

  it "should use default version if none supplied when unmarshalling" do
    packet = RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from', 'request_from', ['try'], true)
    packet.instance_variable_set(:@version, nil)
    MessagePack.load(packet.to_msgpack).send_version.should == RightScale::Packet::DEFAULT_VERSION
    JSON.load(packet.to_json).send_version.should == RightScale::Packet::DEFAULT_VERSION
  end

  it "should be one-way" do
    RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from').one_way.should be_true
  end
end


describe "Packet: Stats" do
  it "should dump/load as MessagePack objects" do
    packet = RightScale::Stats.new(['data'], 'from')
    packet2 = MessagePack.load(packet.to_msgpack)
    packet.data.should == packet2.data
    packet.from.should == packet2.from
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should dump/load as JSON objects" do
    packet = RightScale::Stats.new(['data'], 'from')
    packet2 = JSON.load(packet.to_json)
    packet.data.should == packet2.data
    packet.from.should == packet2.from
    packet.recv_version.should == packet2.recv_version
    packet.send_version.should == packet2.send_version
  end

  it "should use current version by default when constructing" do
    packet = RightScale::Stats.new(['data'], 'from')
    packet.recv_version.should == RightScale::Packet::VERSION
    packet.send_version.should == RightScale::Packet::VERSION
  end

  it "should use default version if none supplied when unmarshalling" do
    packet = RightScale::Stats.new(['data'], 'from')
    packet.instance_variable_set(:@version, nil)
    MessagePack.load(packet.to_msgpack).send_version.should == RightScale::Packet::DEFAULT_VERSION
    JSON.load(packet.to_json).send_version.should == RightScale::Packet::DEFAULT_VERSION
  end

  it "should be one-way" do
    RightScale::Stats.new(['data'], 'from').one_way.should be_true
  end
end
