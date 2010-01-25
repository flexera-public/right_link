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
