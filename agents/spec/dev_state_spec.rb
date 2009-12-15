require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'dev_state'

describe RightScale::DevState do

  include RightScale::SpecHelpers

  it 'should set the "enabled?" flag correctly' do
    RightScale::InstanceState.startup_tags = [ 'some_tag', 'some:machine=tag' ]
    RightScale::DevState.enabled?.should be_false
    RightScale::InstanceState.startup_tags = [ 'some_tag', 'some:machine=tag', 'rs_agent_dev:some_dev_tag=val' ]
    RightScale::DevState.enabled?.should be_true
  end

  it 'should calculate dev tags' do
    RightScale::InstanceState.startup_tags = [ 'rs_agent_dev:cookbooks_path=some_path', 'rs_agent_dev:break_point=some_recipe' ]
    RightScale::DevState.cookbooks_path.should == [ 'some_path' ]
    RightScale::DevState.breakpoint.should == 'some_recipe'
  end

  it 'should determine whether cookbooks path should be used' do
    flexmock(File).should_receive(:directory?).with('some_invalid_path').and_return(false)
    flexmock(File).should_receive(:directory?).with('some_empty_path').and_return(true)
    flexmock(File).should_receive(:directory?).with('some_path').and_return(true)
    flexmock(Dir).should_receive(:entries).with('some_empty_path').and_return(['.','..'])
    flexmock(Dir).should_receive(:entries).with('some_path').and_return('non_empty')

    RightScale::InstanceState.startup_tags = [ 'some_tag' ]
    RightScale::DevState.use_cookbooks_path?.should be_false

    RightScale::InstanceState.startup_tags = [ 'rs_agent_dev:cookbooks_path=some_invalid_path' ]
    RightScale::DevState.use_cookbooks_path?.should be_false

    RightScale::InstanceState.startup_tags = [ 'rs_agent_dev:cookbooks_path=some_empty_path' ]
    RightScale::DevState.use_cookbooks_path?.should be_false

    RightScale::InstanceState.startup_tags = [ 'rs_agent_dev:cookbooks_path=some_path' ]
    RightScale::DevState.use_cookbooks_path?.should be_true
  end

end
