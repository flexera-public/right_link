require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'multiplexer'

describe RightScale::Multiplexer do

  before(:all) do
    @target1 = flexmock('Target 1')
    @target2 = flexmock('Target 2')
    @target3 = flexmock('Target 3')
    @multiplexer = RightScale::Multiplexer.new(@target1, @target2, @target3)
  end

  it 'should multiplex' do
    @target1.should_receive(:some_method).once.with('arg', 'arg2')
    @target2.should_receive(:some_method).once.with('arg', 'arg2')
    @target3.should_receive(:some_method).once.with('arg', 'arg2')
    @multiplexer.some_method('arg', 'arg2')
  end

  it 'should collect results' do
    @target1.should_receive(:some_method).once.with('arg', 'arg2').and_return('res1')
    @target2.should_receive(:some_method).once.with('arg', 'arg2').and_return('res2')
    @target3.should_receive(:some_method).once.with('arg', 'arg2').and_return('res3')
    @multiplexer.some_method('arg', 'arg2').should == [ 'res1', 'res2', 'res3' ]
  end

end