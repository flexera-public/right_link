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
        serializer = RightScale::Serializer.new(format)
        serializer.instance_eval { @serializers.first }.should == MessagePack
      end
    end

    it "supports JSON format" do
      [ :json, "json" ].each do |format|
        serializer = RightScale::Serializer.new(format)
        serializer.instance_eval { @serializers.first }.should == JSON
      end
    end

    it "should default to MessagePack format if not specified" do
      serializer = RightScale::Serializer.new
      serializer.instance_eval { @serializers.first }.should == MessagePack
      serializer = RightScale::Serializer.new(nil)
      serializer.instance_eval { @serializers.first }.should == MessagePack
    end

  end # Format

  describe "Serialization" do

    it "should cascade through available serializers" do
      serializer = RightScale::Serializer.new
      flexmock(serializer).should_receive(:cascade_serializers).with(:dump, "hello").once
      serializer.dump("hello")
    end

    it "should try all supported formats (MessagePack, JSON)" do
      flexmock(MessagePack).should_receive(:dump).with("hello").and_raise(StandardError).once
      flexmock(JSON).should_receive(:dump).with("hello").and_raise(StandardError).once

      lambda { RightScale::Serializer.new.dump("hello") }.should raise_error(RightScale::Serializer::SerializationError)
    end

    it "should raise SerializationError if packet could not be serialized" do
      flexmock(MessagePack).should_receive(:dump).with("hello").and_raise(StandardError).once
      flexmock(JSON).should_receive(:dump).with("hello").and_raise(StandardError).once

      serializer = RightScale::Serializer.new
      lambda { serializer.dump("hello") }.should raise_error(RightScale::Serializer::SerializationError)
    end

    it "should return serialized packet" do
      serialized_packet = flexmock("Packet")
      flexmock(MessagePack).should_receive(:dump).with("hello").and_return(serialized_packet).once

      serializer = RightScale::Serializer.new(:msgpack)
      serializer.dump("hello").should == serialized_packet
    end

  end # Serialization of Packet

  describe "Unserialization" do

    it "should cascade through available serializers" do
      serializer = RightScale::Serializer.new
      flexmock(serializer).should_receive(:cascade_serializers).with(:load, "olleh").once
      serializer.load("olleh")
    end

    it "should try all supported formats (MessagePack, JSON)" do
      flexmock(MessagePack).should_receive(:load).with("olleh").and_raise(StandardError).once
      flexmock(JSON).should_receive(:load).with("olleh").and_raise(StandardError).once

      lambda { RightScale::Serializer.new.load("olleh") }.should raise_error(RightScale::Serializer::SerializationError)
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
