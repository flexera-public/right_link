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

class TestPacket < RightScale::Packet
  @@cls_attr = "ignore"
  def initialize(attr1)
    @attr1 = attr1
  end
end

describe "Packet: Base class" do

  before(:all) do
  end

  it "should be an abstract class" do
    lambda { RightScale::Packet.new }.should raise_error(NotImplementedError, "RightScale::Packet is an abstract class.")
  end

  it "should know how to dump itself to JSON" do
    packet = TestPacket.new(1)
    packet.should respond_to(:to_json)
  end

  it "should dump the class name in 'json_class' JSON key" do
    packet = TestPacket.new(42)
    packet.to_json().should =~ /\"json_class\":\"TestPacket\"/
  end

  it "should dump instance variables in 'data' JSON key" do
    packet = TestPacket.new(188)
    packet.to_json().should =~ /\"data\":\{\"attr1\":188\}/
  end

  it "should not dump class variables" do
    packet = TestPacket.new(382)
    packet.to_json().should_not =~ /cls_attr/
  end

  it "should store instance variables in 'data' JSON key as JSON object" do
    packet = TestPacket.new(382)
    packet.to_json().should =~ /\"data\":\{[\w:"]+\}/
  end

  it "should remove '@' from instance variables" do
    packet = TestPacket.new(2)
    packet.to_json().should_not =~ /@attr1/
    packet.to_json().should =~ /attr1/
  end
end


describe "Packet: Request" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Request.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :reply_to => 'reply_to',
                                     :tries => ['try'], :returns => ["rs-broker-1"])
    packet2 = JSON.parse(packet.to_json)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.reply_to.should == packet2.reply_to
    packet.tries.should == packet2.tries
    packet.returns.should == packet2.returns
    # JSON decoding of floating point sometimes loses accuracy
    (packet.created_at - packet2.created_at).abs.should <= 1.0e-05
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Request.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :reply_to => 'reply_to',
                                     :tries => ['try'], :returns => ["rs-broker-1"])
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.reply_to.should == packet2.reply_to
    packet.tries.should == packet2.tries
    packet.returns.should == packet2.returns
    packet.created_at.should == packet2.created_at
  end

  it "should distinguish multicast request" do
    RightScale::Request.new('/some/foo', 'payload').multicast?.should be_false
    RightScale::Request.new('/some/foo', 'payload', :tags => []).multicast?.should be_false
    RightScale::Request.new('/some/foo', 'payload', :tags => ['tag']).multicast?.should be_true
    RightScale::Request.new('/some/foo', 'payload', :scope => 'scope').multicast?.should be_true
    RightScale::Request.new('/some/foo', 'payload', :selector => 'all').multicast?.should be_true
  end
end


describe "Packet: Push" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Push.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :tries => ['try'],
                                  :returns => ["rs-broker-1"])
    packet2 = JSON.parse(packet.to_json)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tries.should == packet2.tries
    packet.returns.should == packet2.returns
    # JSON decoding of floating point sometimes loses accuracy
    (packet.created_at - packet2.created_at).abs.should <= 1.0e-05
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Push.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :tries => ['try'],
                                  :returns => ["rs-broker-1"])
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tries.should == packet2.tries
    packet.returns.should == packet2.returns
    packet.created_at.should == packet2.created_at
  end

  it "should distinguish multicast request" do
    RightScale::Push.new('/some/foo', 'payload').multicast?.should be_false
    RightScale::Push.new('/some/foo', 'payload', :tags => []).multicast?.should be_false
    RightScale::Push.new('/some/foo', 'payload', :tags => ['tag']).multicast?.should be_true
    RightScale::Push.new('/some/foo', 'payload', :scope => 'scope').multicast?.should be_true
    RightScale::Push.new('/some/foo', 'payload', :selector => 'all').multicast?.should be_true
  end
end


describe "Packet: Result" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from', 'request_from', ['try'], true)
    packet2 = JSON.parse(packet.to_json)
    packet.token.should == packet2.token
    packet.to.should == packet2.to
    packet.results.should == packet2.results
    packet.from.should == packet2.from
    packet.request_from.should == packet2.request_from
    packet.tries.should == packet2.tries
    packet.persistent.should == packet2.persistent
    # JSON decoding of floating point sometimes loses accuracy
    (packet.created_at - packet2.created_at).abs.should <= 1.0e-05
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Result.new('0xdeadbeef', 'to', 'results', 'from', 'request_from', ['try'], true)
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.token.should == packet2.token
    packet.to.should == packet2.to
    packet.results.should == packet2.results
    packet.from.should == packet2.from
    packet.request_from.should == packet2.request_from
    packet.tries.should == packet2.tries
    packet.persistent.should == packet2.persistent
    packet.created_at.should == packet2.created_at
  end
end


describe "Packet: Stale" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Stale.new('0xdeadbeef', 'token', 'from', 12345678, 87654321, 900)
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
    packet.token.should == packet2.token
    packet.from.should == packet2.from
    packet.timeout.should == packet2.timeout
    # JSON decoding of floating point sometimes loses accuracy
    (packet.created_at - packet2.created_at).abs.should <= 1.0e-05
    (packet.received_at - packet2.received_at).abs.should <= 1.0e-05
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Stale.new('0xdeadbeef', 'token', 'from', 12345678, 87654321, 900)
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
    packet.token.should == packet2.token
    packet.from.should == packet2.from
    packet.timeout.should == packet2.timeout
    packet.created_at.should == packet2.created_at
    packet.received_at.should == packet2.received_at
  end
end


describe "Packet: Register" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Register.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], ['b1', 'b2'])
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
    packet.services.should == packet2.services
    packet.status.should == packet2.status
    packet.brokers.should == packet2.brokers
    packet.shared_queue.should == packet2.shared_queue
    # JSON decoding of floating point sometimes loses accuracy
    (packet.created_at - packet2.created_at).abs.should <= 1.0e-05
    packet.version.should == packet2.version
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Register.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], nil, 'shared')
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
    packet.services.should == packet2.services
    packet.status.should == packet2.status
    packet.brokers.should == packet2.brokers
    packet.shared_queue.should == packet2.shared_queue
    packet.created_at.should == packet2.created_at
    packet.version.should == packet2.version
  end

  it "should set specified shared_queue" do
    packet = RightScale::Register.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], nil, 'shared')
    packet.shared_queue.should == 'shared'
  end

  it "should default shared_queue to nil" do
    packet = RightScale::Register.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], nil)
    packet.shared_queue.should be_nil
   end

  it "should use current version by default when constructing" do
    packet = RightScale::Register.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], nil, 'shared', nil)
    packet.version == RightScale::Packet::VERSION
  end

  it "should use default version if none supplied when unmarshalling" do
    packet = RightScale::Register.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], nil, 'shared', nil)
    JSON.parse(packet.to_json).version == RightScale::Packet::DEFAULT_VERSION
    Marshal.load(Marshal.dump(packet)).version == RightScale::Packet::DEFAULT_VERSION
  end
end


describe "Packet: UnRegister" do
  it "should dump/load as JSON objects" do
    packet = RightScale::UnRegister.new('0xdeadbeef')
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::UnRegister.new('0xdeadbeef')
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
  end
end


describe "Packet: Ping" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Ping.new('0xdeadbeef', 0.8, ['b1', 'b2'], ['b3'])
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
    packet.status.should == packet2.status
    packet.connected.should == packet2.connected
    packet.failed.should == packet2.failed
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Ping.new('0xdeadbeef', 0.8)
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
    packet.status.should == packet2.status
    packet.connected.should == packet2.connected
    packet.failed.should == packet2.failed
  end
end


describe "Packet: Advertise" do
  it "should dump/load as JSON objects" do
    packet = RightScale::Advertise.new
    packet2 = JSON.parse(packet.to_json)
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::Advertise.new
    packet2 = Marshal.load(Marshal.dump(packet))
  end
end


describe "Packet: TagUpdate" do
  it "should dump/load as JSON objects" do
    packet = RightScale::TagUpdate.new('from', [ 'one', 'two'] , [ 'zero'])
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
    packet.new_tags.should == packet2.new_tags
    packet.obsolete_tags.should == packet2.obsolete_tags
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::TagUpdate.new('from', [ 'one', 'two'] , [ 'zero'])
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
    packet.new_tags.should == packet2.new_tags
    packet.obsolete_tags.should == packet2.obsolete_tags
  end
end


describe "Packet: TagQuery" do
  it "should dump/load as JSON objects" do
    packet = RightScale::TagQuery.new('from', :token => '0xdeadbeef', :tags => [ 'one', 'two'] , :agent_ids => [ 'some_agent', 'some_other_agent'])
    packet2 = JSON.parse(packet.to_json)
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tags.should == packet2.tags
    packet.agent_ids.should == packet2.agent_ids
    packet.persistent.should == packet2.persistent
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::TagQuery.new('from', :token => '0xdeadbeef', :tags => [ 'one', 'two'] , :agent_ids => [ 'some_agent', 'some_other_agent'])
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tags.should == packet2.tags
    packet.agent_ids.should == packet2.agent_ids
    packet.persistent.should == packet2.persistent
  end
end
