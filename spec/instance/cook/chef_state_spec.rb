#
# Copyright (c) 2009-2011 RightScale Inc
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

describe RightScale::ChefState do

  include RightScale::SpecHelper

  it_should_behave_like 'mocks cook'

  before(:all) do
    flexmock(RightScale::Log).should_receive(:debug)
  end

  before(:each) do
    setup_state
    @old_chef_file = RightScale::ChefState::STATE_FILE
    @chef_file = File.join(File.dirname(__FILE__), '__chef.js')
    RightScale::ChefState.const_set(:STATE_FILE, @chef_file)
  end

  after(:each) do
    RightScale::ChefState.attributes = {}
    File.delete(@chef_file) if File.file?(@chef_file)
    RightScale::ChefState::const_set(:STATE_FILE, @old_chef_file)
    cleanup_state
  end

  it 'should initialize' do
    RightScale::ChefState.init(true)
    RightScale::ChefState.attributes.should == {}
  end

  it 'should reset' do
    RightScale::ChefState.attributes = { :one => 'two' }
    RightScale::ChefState.attributes.should == { :one => 'two' }
    RightScale::ChefState.init(reset=true)
    RightScale::ChefState.attributes.should == {}
  end

  it 'should merge attributes' do
    RightScale::ChefState.attributes = { :one => 'two' }
    RightScale::ChefState.merge_attributes({ :two => 'three' })
    RightScale::ChefState.attributes.should == { :one => 'two', :two => 'three' }
    RightScale::ChefState.merge_attributes({ :two => 'three' })
    RightScale::ChefState.attributes.should == { :one => 'two', :two => 'three' }
  end

  it 'should persist the state' do
    RightScale::ChefState.attributes = { :one => 'two' }
    JSON.load(IO.read(@chef_file)).should == { 'attributes' => { 'one' => 'two' } }
  end

  it 'should not persist the state if cook does not hold the default lock' do
    @mock_cook.mock_attributes[:thread_name] = 'backup'
    RightScale::ChefState.attributes = { :one => 'two' }
    File.file?(@chef_file).should be_false
  end

  it 'persisted state should only be readable by the owner' do
    RightScale::ChefState.attributes = { :one => 'two' }
    expected_perms = (RightScale::Platform.windows?) ? 0644 : 0600
    (File.stat(@chef_file).mode & 0777).should == expected_perms
  end

  it 'should change the permissions of the state file to only be readable by the owner' do
    FileUtils.touch(@chef_file)
    File.chmod(0666, @chef_file)
    RightScale::ChefState.attributes = { :one => 'two' }
    expected_perms = (RightScale::Platform.windows?) ? 0644 : 0600
    (File.stat(@chef_file).mode & 0777).should == expected_perms
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
