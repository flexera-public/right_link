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


describe "Packet: RequestPacket" do
  it "should dump/load as JSON objects" do
    packet = RightScale::RequestPacket.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :reply_to => 'reply_to')
    packet2 = JSON.parse(packet.to_json)
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.reply_to.should == packet2.reply_to
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::RequestPacket.new('/some/foo', 'payload', :from => 'from', :token => '0xdeadbeef', :reply_to => 'reply_to')
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.type.should == packet2.type
    packet.payload.should == packet2.payload
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.reply_to.should == packet2.reply_to
  end
end


describe "Packet: TagQueryPacket" do
  it "should dump/load as JSON objects" do
    packet = RightScale::TagQueryPacket.new('from', :token => '0xdeadbeef', :tags => [ 'one', 'two'] , :agent_ids => [ 'some_agent', 'some_other_agent'])
    packet2 = JSON.parse(packet.to_json)
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tags.should == packet2.tags
    packet.agent_ids.should == packet2.agent_ids
    packet.persistent.should == packet2.persistent
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::TagQueryPacket.new('from', :token => '0xdeadbeef', :tags => [ 'one', 'two'] , :agent_ids => [ 'some_agent', 'some_other_agent'])
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.from.should == packet2.from
    packet.token.should == packet2.token
    packet.tags.should == packet2.tags
    packet.agent_ids.should == packet2.agent_ids
    packet.persistent.should == packet2.persistent
  end
end


describe "Packet: ResultPacket" do
  it "should dump/load as JSON objects" do
    packet = RightScale::ResultPacket.new('0xdeadbeef', 'to', 'results', 'from')
    packet2 = JSON.parse(packet.to_json)
    packet.token.should == packet2.token
    packet.to.should == packet2.to
    packet.results.should == packet2.results
    packet.from.should == packet2.from
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::ResultPacket.new('0xdeadbeef', 'to', 'results', 'from')
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.token.should == packet2.token
    packet.to.should == packet2.to
    packet.results.should == packet2.results
    packet.from.should == packet2.from
  end
end


describe "Packet: RegisterPacket" do
  it "should dump/load as JSON objects" do
    packet = RightScale::RegisterPacket.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], '0xdeadbeef')
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
    packet.services.should == packet2.services
    packet.status.should == packet2.status
    packet.queue.should == packet2.queue
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::RegisterPacket.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], 'queue')
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
    packet.services.should == packet2.services
    packet.status.should == packet2.status
    packet.queue.should == packet2.queue
  end

  it "should set specified queue" do
    packet = RightScale::RegisterPacket.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], 'queue')
    packet.queue.should == 'queue'
  end

  it "should default queue to identity" do
    packet = RightScale::RegisterPacket.new('0xdeadbeef', ['/foo/bar', '/nik/qux'], 0.8, ['foo'], nil)
    packet.queue.should == '0xdeadbeef'
   end
 end


describe "Packet: UnRegisterPacket" do
  it "should dump/load as JSON objects" do
    packet = RightScale::UnRegisterPacket.new('0xdeadbeef')
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::UnRegisterPacket.new('0xdeadbeef')
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
  end
end


describe "Packet: PingPacket" do
  it "should dump/load as JSON objects" do
    packet = RightScale::PingPacket.new('0xdeadbeef', 0.8)
    packet2 = JSON.parse(packet.to_json)
    packet.identity.should == packet2.identity
    packet.status.should == packet2.status
  end

  it "should dump/load as Marshalled ruby objects" do
    packet = RightScale::PingPacket.new('0xdeadbeef', 0.8)
    packet2 = Marshal.load(Marshal.dump(packet))
    packet.identity.should == packet2.identity
    packet.status.should == packet2.status
  end
end
