require File.join(File.dirname(__FILE__), 'spec_helper')

describe RightScale::CommandSerializer do

  before(:all) do
    @sample_data = [ 42, 'fourty two', { :haha => 42, 'hoho' => 'fourty_two' }]
  end

  it 'should serialize' do
    @sample_data.each do |data|
      RightScale::CommandSerializer.dump(data)
    end
  end

  it 'should deserialize' do
    @sample_data.each do |data|
      RightScale::CommandSerializer.load(RightScale::CommandSerializer.dump(data)).should == data
    end
  end

  it 'should add separators' do
    serialized = ''
    @sample_data.each do |data|
      serialized << RightScale::CommandSerializer.dump(data)
    end
    serialized.split(RightScale::CommandSerializer::SEPARATOR).size.should == @sample_data.size
  end

end
