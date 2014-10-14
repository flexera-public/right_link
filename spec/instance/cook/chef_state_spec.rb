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

require File.expand_path('../spec_helper', __FILE__)

describe RightScale::ChefState do

  include RightScale::SpecHelper

  it_should_behave_like 'mocks cook'

  before(:all) do
    flexmock(RightScale::Log).should_receive(:debug)
  end

  let(:agent_identity) { 'rs-instance-1-1' }

  before(:each) do
    setup_state(agent_identity)
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
    RightScale::ChefState.init(agent_identity, secret='some secret', reset=true)
    RightScale::ChefState.attributes.should == {}
  end

  it 'should reset' do
    RightScale::ChefState.attributes = { :one => 'two' }
    RightScale::ChefState.attributes.should == { :one => 'two' }
    RightScale::ChefState.init(agent_identity, secret='some secret', reset=true)
    RightScale::ChefState.attributes.should == {}
  end

  it 'should merge attributes' do
    RightScale::ChefState.attributes = { :one => 'two' }
    RightScale::ChefState.merge_attributes({ :two => 'three' })
    RightScale::ChefState.attributes.should == { :one => 'two', :two => 'three' }
    RightScale::ChefState.merge_attributes({ :two => 'three' })
    RightScale::ChefState.attributes.should == { :one => 'two', :two => 'three' }
  end

  it 'should state should not be directly readable' do
    File.exists?(@chef_file).should be_false
    RightScale::ChefState.attributes = { :one => 'two' }
    File.exists?(@chef_file).should be_true
    data = IO.read(@chef_file)
    (data =~ /one/).should be_false
    (data =~ /two/).should be_false
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
end
