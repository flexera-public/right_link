require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'chef_state'
require 'dev_state'
require 'request_forwarder'
require 'right_link_log'

describe RightScale::ChefState do

  include RightScale::SpecHelpers

  before(:all) do
    flexmock(RightScale::RightLinkLog).should_receive(:debug)
  end

  before(:each) do
    setup_state
    @old_chef_file = RightScale::ChefState::STATE_FILE
    @chef_file = File.join(File.dirname(__FILE__), '__chef.js')
    RightScale::ChefState.const_set(:STATE_FILE, @chef_file)
  end

  after(:each) do
    RightScale::ChefState.run_list = []
    RightScale::ChefState.attributes = {}
    File.delete(@chef_file) if File.file?(@chef_file)
    RightScale::ChefState::const_set(:STATE_FILE, @old_chef_file)
    cleanup_state
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

  it 'should merge run lists' do
    RightScale::ChefState.run_list = [ 1, 2, 3, 4 ]
    RightScale::ChefState.merge_run_list([3, 5])
    RightScale::ChefState.run_list.should == [ 1, 2, 3, 4, 5 ]
    RightScale::ChefState.merge_run_list([1,2, 3, 5, 6])
    RightScale::ChefState.run_list.should == [ 1, 2, 3, 4, 5, 6 ]
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

  it 'should create patch from hashes' do
    patches.each { |p| RightScale::ChefState.create_patch(p[:left], p[:right]).should == p[:res] }
  end

  it 'should apply patches' do
    applied_patches.each { |p| RightScale::ChefState.apply_patch(p[:target], p[:patch]).should == p[:res] }
  end

  # Test battery for patch creation
  def patches
    [ {
      # Identical
      :left  => { :one => 1 },
      :right => { :one => 1 },
      :res   => { :left_only  => {},
                  :right_only => {},
                  :diff       => {} }
      }, {
      # Disjoint
      :left  => { :one => 1 },
      :right => { :two => 1 },
      :res   => { :left_only  => { :one => 1},
                  :right_only => { :two => 1},
                  :diff       => {} }
      }, {
      # Value diff
      :left  => { :one => 1 },
      :right => { :one => 2 },
      :res   => { :left_only  => {},
                  :right_only => {},
                  :diff       => { :one => { :left => 1, :right => 2} } }
      }, {
      # Recursive disjoint
      :left  => { :one => { :a => 1, :b => 2 }, :two => 3 },
      :right => { :one => { :a => 1 }, :two => 3 },
      :res   => { :left_only  => { :one => { :b => 2 }},
                  :right_only => {},
                  :diff       => {} }
      }, {
      # Recursive value diff
      :left  => { :one => { :a => 1, :b => 2 }, :two => 3 },
      :right => { :one => { :a => 1, :b => 3 }, :two => 3 },
      :res   => { :left_only  => {},
                  :right_only => {},
                  :diff       => { :one => { :b => { :left => 2, :right => 3 }} } }
      }, {
      # Recursive disjoint and value diff
      :left  => { :one => { :a => 1, :b => 2, :c => 3 }, :two => 3, :three => 4 },
      :right => { :one => { :a => 1, :b => 3, :d => 4 }, :two => 5, :four => 6 },
      :res   => { :left_only  => { :one => { :c => 3 }, :three => 4 },
                  :right_only => { :one => { :d => 4 }, :four => 6 },
                  :diff       => { :one => { :b => { :left => 2, :right => 3 }}, :two => { :left => 3, :right => 5 }} }
      }
    ]
  end

  # Test battery for patch application
  def applied_patches
    [
      {
        # Empty patch
        :target => { :one => 1 },
        :patch  => { :left_only => {}, :right_only => {}, :diff => {} },
        :res    => { :one => 1}
      }, {
        # Disjoint
        :target => { :one => 1 },
        :patch  => { :left_only => { :one => 2 }, :right_only => {}, :diff => { :one => { :left => 3, :right => 4 }} },
        :res    => { :one => 1 }
      }, {
        # Removal
        :target => { :one => 1 },
        :patch  => { :left_only => { :one => 1 }, :right_only => {}, :diff => {} },
        :res    => {}
      }, {
        # Addition
        :target => { :one => 1 },
        :patch  => { :left_only => {}, :right_only => { :two => 2 }, :diff => {} },
        :res    => { :one => 1, :two => 2 }
      }, {
        # Substitution
        :target => { :one => 1 },
        :patch  => { :left_only => {}, :right_only => {}, :diff => { :one => { :left => 1, :right => 2} } },
        :res    => { :one => 2 }
      }, {
        # Recursive removal
        :target => { :one => { :a => 1, :b => 2 } },
        :patch  => { :left_only => { :one => { :a => 1 }}, :right_only => {}, :diff => {} },
        :res    => { :one => { :b => 2 } }
      }, {
        # Recursive addition
        :target => { :one => { :a => 1 } },
        :patch  => { :left_only => {}, :right_only => { :one => { :b => 2 } }, :diff => {} },
        :res    => { :one => { :a => 1, :b => 2 } }
      }, {
        # Recursive substitution
        :target => { :one => { :a => 1 } },
        :patch  => { :left_only => {}, :right_only => {}, :diff => { :one => { :a => { :left => 1, :right => 2 }} } },
        :res    => { :one => { :a => 2 } }
      }, {
        # Combined
        :target => { :one => { :a => 1, :b => 2 } },
        :patch  => { :left_only => { :one => { :a => 1 } }, :right_only => { :one => { :c => 3 }}, :diff => { :one => { :b => { :left => 2, :right => 3 }} } },
        :res    => { :one => { :b => 3, :c => 3 } }
      }
    ]
  end
end
