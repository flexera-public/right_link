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
    parts = data[0..2], data[3..4], data[5..6], data[7..data.size - 1]
    command = ''
    parser = RightScale::CommandParser.new { |cmd| command = cmd; EM.stop }
    EM.run do
      parts.each { |p| parser.parse_chunk(p) }
      EM.add_timer(0.5) { EM.stop }
    end
    command.should == { :some => 'random', :and => 'long', :serialized => 'data' }
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
