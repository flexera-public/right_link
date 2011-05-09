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

describe RightScale::CommandParser do

  it 'should detect missing block' do
    lambda { RightScale::CommandParser.new }.should raise_error(RightScale::Exceptions::Argument)
  end

  it 'should parse' do
    @parser = RightScale::CommandParser.new { |cmd| @command = cmd; EM.stop }
    EM.run do
      @parser.parse_chunk(RightScale::CommandSerializer.dump(42)).should be_true
      EM.add_timer(0.5) { EM.stop }
    end
    @command.should == 42
  end

  it 'should parse in chunks' do
    data = RightScale::CommandSerializer.dump({ :some => 'random', :and => 'long', :serialized => 'data' })
    data.size.should > 6
    separator_length = RightScale::CommandSerializer::SEPARATOR.size
    parts = data[0..2], data[3..4], data[5..6],
            data[7..(data.size - separator_length - 1)],
            data[(data.size - separator_length)..-1]

    # duplicate the parts but join last part of the first command to the first
    # part of the second command to simluate EM truncating a large data chunk
    # due to buffer restrictions. this creates a part which contains the command
    # separator followed by an incomplete (and therefore invalid) start-of-YAML-
    # doc separator which raises a YAML exception if parsed. this tests that our
    # parser will wait for more parts before parsing the second command.
    parts = parts[0..-2] + [parts[-1] + parts[0]] + parts[1..-1]

    commands = []
    parser = RightScale::CommandParser.new do |cmd|
      commands << cmd
      EM.stop if commands.size >= 2
    end
    EM.run do
      parts.each { |p| parser.parse_chunk(p) }
      EM.add_timer(1) { EM.stop }
    end
    commands.size.should == 2
    commands.each do |command|
      command.should == { :some => 'random', :and => 'long', :serialized => 'data' }
    end
  end

  it 'should parse multiple commands' do
    commands = []
    sample_data = [42, {:question => 'why?', :answer => 'fourty-two'}]
    parser = RightScale::CommandParser.new { |cmd| commands << cmd; EM.stop if commands.size == sample_data.size }
    serialized = sample_data.inject('') { |s, cmd| s << RightScale::CommandSerializer.dump(cmd) }
    EM.run do
      parser.parse_chunk(serialized).should be_true
      EM.add_timer(0.5) { EM.stop }
    end
    commands.should == sample_data
  end

  it 'should parse multiple commands in chunks' do
    commands = []
    sample_data = [42, {:question => 'why?', :answer => 'fourty-two'}]
    parser = RightScale::CommandParser.new { |cmd| commands << cmd; EM.stop if commands.size == sample_data.size }
    serialized = sample_data.inject('') { |s, cmd| s << RightScale::CommandSerializer.dump(cmd) }
    serialized.size.should > 10
    parts = serialized[0..2], serialized[3..4], serialized[5..6], serialized[7..serialized.size - 5], serialized[serialized.size - 4..serialized.size - 1]
    EM.run do
      parts.each { |p| parser.parse_chunk(p) }
      EM.add_timer(0.5) { EM.stop }
    end
    commands.should == sample_data
  end

end
