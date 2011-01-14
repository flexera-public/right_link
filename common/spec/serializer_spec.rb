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

describe RightScale::Serializer do

  describe "Format" do

    it "supports MessagePack format" do
      [ :msgpack, "msgpack" ].each do |format|
        lambda { RightScale::Serializer.new(format).format.should == :msgpack }.should_not raise_error
      end
    end

    it "supports JSON format" do
      [ :json, "json" ].each do |format|
        lambda { RightScale::Serializer.new(format).format.should == :json }.should_not raise_error
      end
    end

    it "supports secure format" do
      [ :secure, "secure" ].each do |format|
        lambda { RightScale::Serializer.new(format).format.should == :secure }.should_not raise_error
      end
    end

    it "should default to MessagePack format if none specified" do
      RightScale::Serializer.new.format.should == :msgpack
    end

    it "should raise error if unsupported format specified" do
      lambda { RightScale::Serializer.new(:yaml) }.should raise_error(ArgumentError)
    end

  end # Format

  describe "Serialization" do

    it "should use MessagePack as default serializer and not cascade to others" do
      serializer = RightScale::Serializer.new
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello", [MessagePack]).once
      serializer.dump("hello")
    end

    it "should use preferred serializer if specified and not cascade to others" do
      serializer = RightScale::Serializer.new(:json)
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello", [JSON]).once
      serializer.dump("hello")
    end

    it "should raise SerializationError if packet could not be serialized and not try other serializer" do
      flexmock(MessagePack).should_receive(:dump).with("hello").and_raise(StandardError).once
      flexmock(JSON).should_receive(:dump).with("hello").and_raise(StandardError).once
      serializer = RightScale::Serializer.new(:msgpack)
      lambda { serializer.dump("hello") }.should raise_error(RightScale::Serializer::SerializationError)
      serializer = RightScale::Serializer.new(:json)
      lambda { serializer.dump("hello") }.should raise_error(RightScale::Serializer::SerializationError)
    end

    it "should return serialized packet" do
      serialized_packet = flexmock("Packet")
      flexmock(MessagePack).should_receive(:dump).with("hello").and_return(serialized_packet).once
      serializer = RightScale::Serializer.new
      serializer.dump("hello").should == serialized_packet
    end

    it "should be able to override preferred format" do
      serializer = RightScale::Serializer.new(:json)
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello", [MessagePack]).once
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello", [JSON]).never
      serializer.dump("hello", :msgpack)
    end

    it "should not be able to override preferred format when secure" do
      serializer = RightScale::Serializer.new(:secure)
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello", [RightScale::SecureSerializer]).once
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello", [MessagePack]).never
      serializer.dump("hello", :msgpack)
    end

    describe "MessagePack for common classes" do

      it "should serialize Date object" do
        serializer = RightScale::Serializer.new(:msgpack)
        date = Date.today
        data = serializer.dump(date)
        Date.parse(serializer.load(data)).should == date
      end

      it "should serialize Time object" do
        serializer = RightScale::Serializer.new(:msgpack)
        time = Time.now
        data = serializer.dump(time)
        Time.parse(serializer.load(data)).to_i.should == time.to_i
      end

      it "should serialize DateTime object" do
        serializer = RightScale::Serializer.new(:msgpack)
        date_time = DateTime.now
        data = serializer.dump(date_time)
        DateTime.parse(serializer.load(data)).to_s.should == date_time.to_s
      end

    end

  end # Serialization of Packet

  describe "Unserialization" do

    it "should cascade through available serializers" do
      serializer = RightScale::Serializer.new
      flexmock(serializer).should_receive(:cascade_serializers).with(:load, "olleh", [JSON, MessagePack]).once
      serializer.load("olleh")
    end

    it "should try all supported formats (MessagePack, JSON)" do
      flexmock(MessagePack).should_receive(:load).with("olleh").and_raise(StandardError).once
      flexmock(JSON).should_receive(:load).with("olleh").and_raise(StandardError).once
      lambda { RightScale::Serializer.new.load("olleh") }.should raise_error(RightScale::Serializer::SerializationError)
    end

    it "should try JSON format first if looks like JSON even if MessagePack preferred" do
      object = [1, 2, 3]
      serialized = object.to_json
      flexmock(MessagePack).should_receive(:load).with(serialized).never
      flexmock(JSON).should_receive(:load).with(serialized).and_return(object).once
      RightScale::Serializer.new(:msgpack).load(serialized)
    end

    it "should try MessagePack format first if looks like MessagePack even if JSON preferred" do
      object = [1, 2, 3]
      serialized = object.to_msgpack
      flexmock(JSON).should_receive(:load).with(serialized).never
      flexmock(MessagePack).should_receive(:load).with(serialized).and_return(object).once
      RightScale::Serializer.new(:json).load(serialized)
    end

    it "should raise SerializationError if packet could not be unserialized" do
      flexmock(MessagePack).should_receive(:load).with("olleh").and_raise(StandardError).once
      flexmock(JSON).should_receive(:load).with("olleh").and_raise(StandardError).once
      serializer = RightScale::Serializer.new
      lambda { serializer.load("olleh") }.should raise_error(RightScale::Serializer::SerializationError)
    end

    it "should return unserialized packet" do
      unserialized_packet = flexmock("Packet")
      flexmock(MessagePack).should_receive(:load).with("olleh").and_return(unserialized_packet).once
      serializer = RightScale::Serializer.new(:msgpack)
      serializer.load("olleh").should == unserialized_packet
    end

  end # De-Serialization of Packet

end # RightScale::Serializer
