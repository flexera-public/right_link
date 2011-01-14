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
require File.join(File.dirname(__FILE__), '..', 'lib', 'common', 'message_pack')
require File.join(File.dirname(__FILE__), '..', 'lib', 'common', 'serializable')

module RightScale
  class TestClass
    include Serializable

    attr_accessor :var1, :var2

    def initialize(*a)
      @var1 = a[0]
      @var2 = a[1]
    end

    def serialized_members
      [@var1, @var2]
    end

    def ==(rhs)
      @var1 == rhs.var1 && @var2 == rhs.var2
    end
  end
end

class NonSerializableTestClass
  attr_accessor :var1

  def initialize(*a)
    @var1 = a[0]
  end

  def to_msgpack(*a)
    {
      'msgpack_class' => self.class.name,
      'data'          => serialized_members
    }.to_msgpack(*a)
  end

  def serialized_members
    [@var1]
  end
end

describe MessagePack do

  it "should serialize an object when dump and unserialize when load to produce equivalent object" do
    object = [1, 3.14, {"key" => "value"}]
    MessagePack.load(MessagePack.dump(object)).should == object
  end

  it "should behave like JSON in terms of not preserving symbols" do
    object = [1, 3.14, {:key => "value"}]
    MessagePack.load(MessagePack.dump(object)).should == [1, 3.14, {"key" => "value"}]
  end

  it "should serialize arbitrary objects when dump and recreate when load" do
    object = RightScale::TestClass.new({"key" => "value"}, [1, 2, "abc"])
    data = MessagePack.dump(object)
    (data =~ /msgpack_class.*RightScale::TestClass/).should be_true
    MessagePack.load(data).should == object
  end

  it "should do nested creation of objects within arrays" do
    test = RightScale::TestClass.new({"key" => "value"}, [1, 2, "abc"])
    object = [1, 3.14, test]
    data = MessagePack.dump(object)
    (data =~ /msgpack_class.*RightScale::TestClass/).should be_true
    MessagePack.load(data).should == object
  end

  it "should do nested creation of objects within hashes" do
    test = RightScale::TestClass.new({"key" => "value"}, [1, 2, "abc"])
    object = {"my_data" => [99, 4.3, 712345], "my_test" => test}
    data = MessagePack.dump(object)
    (data =~ /msgpack_class.*RightScale::TestClass/).should be_true
    MessagePack.load(data).should == object
  end

  it "should do nested creation of objects recursively" do
    test1 = RightScale::TestClass.new("some", "test")
    test2 = RightScale::TestClass.new({"key" => "value"}, [1, 2, "abc"])
    object = [{"my_data" => [99, 4.3, 712345], "my_tests" => {"test1" => test1, "test2" => test2}}, test1, test2]
    data = MessagePack.dump(object)
    (data =~ /msgpack_class.*RightScale::TestClass/).should be_true
    MessagePack.load(data).should == object
  end

  it "should do nested creation of objects that are arguments in the creation of nested objects" do
    test1 = RightScale::TestClass.new("some", "test")
    test2 = RightScale::TestClass.new({"key" => "value"}, test1)
    object = [{"my_data" => [99, 4.3, 712345], "my_tests" => {"test1" => test1, "test2" => test2}}, test1, test2]
    data = MessagePack.dump(object)
    (data =~ /msgpack_class.*RightScale::TestClass/).should be_true
    MessagePack.load(data).should == object
  end

  it "should raise an exception if it finds a msgpack_class but there is no msgpack_generate method" do
    data = MessagePack.dump(NonSerializableTestClass.new(nil))
    (data =~ /msgpack_class.*NonSerializableTestClass/).should be_true
    lambda { MessagePack.load(data) }.should raise_error(ArgumentError, /missing msgpack_create method/)
  end

  it "should raise an exception if it cannot resolve a named msgpack_class" do
    object = [1, 3.14, {"msgpack_class" => "RightScale::BogusClass"}]
    data = MessagePack.dump(object)
    (data =~ /msgpack_class.*RightScale::BogusClass/).should be_true
    lambda { MessagePack.load(data) }.should raise_error(ArgumentError, /Cannot find const/)
  end

end
