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

describe String do

  describe ".snake_case" do

    it "should downcase single word" do
      ["FOO", "Foo", "foo"].each do |w|
        w.snake_case.should == "foo"
      end
    end

    it "should not separate numbers from end of word" do
      ["Foo1234", "foo1234"].each do |w|
        w.snake_case.should == "foo1234"
      end
    end

    it "should not separate numbers from word that starts with uppercase letter" do
      "1234Foo".snake_case.should == "1234foo"
    end

    it "should not separate numbers from word that starts with lowercase letter" do
      "1234foo".snake_case.should == "1234foo"
    end

    it "should downcase camel-cased words and connect with underscore" do
      ["FooBar", "fooBar"].each do |w|
        w.snake_case.should == "foo_bar"
      end
    end

    it "should start new word with uppercase letter before lower case letter" do
      ["FooBARBaz", "fooBARBaz"].each do |w|
        w.snake_case.should == "foo_bar_baz"
      end
    end

  end

  describe ".to_const_path" do

    it "should snake-case the string" do
      "Hello::World".to_const_path.should == "hello/world"
    end

    it "should leave (snake-cased) string without '::' unchanged" do
      "hello".to_const_path.should == "hello"
    end

    it "should replace single '::' with '/'" do
      "hello::world".to_const_path.should == "hello/world"
    end
    
    it "should replace multiple '::' with '/'" do
      "hello::rightscale::world".to_const_path.should == "hello/rightscale/world"
    end

  end

  describe '.camelize' do

    it 'should camelize the string' do
      'hello/world_hello'.camelize.should == 'Hello::WorldHello'
    end

    it 'should camelize strings with integers' do
      '1hel2lo3/4wor5ld6_7hel8lo9'.camelize.should == '1hel2lo3::4wor5ld67hel8lo9'
    end

    it 'should leave camelized strings alone' do
      '1Hel2lo3::4Wor5ld67Hel8lo9'.camelize.should == '1Hel2lo3::4Wor5ld67Hel8lo9'
    end
    
  end

end # String
