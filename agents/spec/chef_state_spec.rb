require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'chef_state'
require 'right_link_log'

describe RightScale::ChefState do

  include RightScale::SpecHelpers

  before(:all) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
  end

  before(:each) do
    @old_chef_file = RightScale::ChefState::STATE_FILE
    @chef_file = File.join(File.dirname(__FILE__), '__chef.js')
    RightScale::ChefState.const_set(:STATE_FILE, @chef_file)
  end

  after(:each) do
    File.delete(@chef_file) if File.file?(@chef_file)
    RightScale::ChefState::const_set(:STATE_FILE, @old_chef_file)
  end

  it 'should initialize' do
    RightScale::ChefState.init
    RightScale::ChefState.run_list.should == []
    RightScale::ChefState.attributes.should == {}
  end

  it 'should reset' do
    RightScale::ChefState.run_list = [ 1, 2, 3, 4 ]
    RightScale::ChefState.attributes = { :one => 'two' }
    RightScale::ChefState.run_list.should == [ 1, 2, 3, 4 ]
    RightScale::ChefState.attributes.should == { :one => 'two' }
    RightScale::ChefState.init(reset=true)
    RightScale::ChefState.run_list.should == []
    RightScale::ChefState.attributes.should == {}
  end

  it 'should merge recipes into the run list' do
    RightScale::ChefState.run_list = [ 1, 2, 3, 4 ]
    RightScale::ChefState.merge_recipe(5)
    RightScale::ChefState.run_list.should == [ 1, 2, 3, 4, 5 ]
    RightScale::ChefState.merge_recipe(5)
    RightScale::ChefState.run_list.should == [ 1, 2, 3, 4, 5 ]
  end

  it 'should merge attributes' do
    RightScale::ChefState.attributes = { :one => 'two' }
    RightScale::ChefState.merge_attributes({ :two => 'three' })
    RightScale::ChefState.attributes.should == { :one => 'two', :two => 'three' }
    RightScale::ChefState.merge_attributes({ :two => 'three' })
    RightScale::ChefState.attributes.should == { :one => 'two', :two => 'three' }
  end

  it 'should persist the state' do
    RightScale::ChefState.run_list = [ 1, 2, 3, 4 ]
    RightScale::ChefState.attributes = { :one => 'two' }
    JSON.load(IO.read(@chef_file)).should == { 'run_list' => [ 1, 2, 3, 4 ], 'attributes' => { 'one' => 'two' } }
  end

end
