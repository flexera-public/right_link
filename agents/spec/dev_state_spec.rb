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

#monkey patch DevState and add a reset method for testing
module RightScale
  class DevState
    def self.reset
      @@initialized = false
    end
  end
end

describe RightScale::DevState do

  include RightScale::SpecHelpers

  before :each do
    #re-initialize instance state
    RightScale::InstanceState.init(@identity)

    #re-initialize dev state
    FileUtils.rm_f(RightScale::DevState::STATE_FILE)
    RightScale::DevState.reset
  end

  after :each do
    FileUtils.rm_f(RightScale::DevState::STATE_FILE)
  end

  shared_examples_for "nothing is set" do
    it 'should not have a cookbooks path' do
      RightScale::DevState.cookbooks_path.should be_nil
    end

    it 'should not have a breakpoint' do
      RightScale::DevState.breakpoint.should be_nil
    end

    it 'should not use cookbooks path' do
      RightScale::DevState.use_cookbooks_path?.should be_false
    end

    it 'should download cookbooks' do
      RightScale::DevState.download_cookbooks?.should be_true
    end
  end

  shared_examples_for "dev state is enabled" do
    it 'should be enabled' do
      RightScale::DevState.enabled?.should be_true
    end
  end

  shared_examples_for "dev state is disabled" do
    it 'should not be enabled' do
      RightScale::DevState.enabled?.should be_false
    end
  end

  shared_examples_for "has no cookbooks path" do
    it 'should not use cookbooks path' do
      RightScale::DevState.use_cookbooks_path?.should be_false
    end

    it 'should download cookbooks' do
      RightScale::DevState.download_cookbooks?.should be_true
    end
  end

  shared_examples_for "has a valid cookbooks path" do
    before :each do
      RightScale::InstanceState.startup_tags = RightScale::InstanceState.startup_tags << 'rs_agent_dev:cookbooks_path=some_path'

      flexmock(File).should_receive(:directory?).with('some_path').and_return(true)
      flexmock(Dir).should_receive(:entries).with('some_path').and_return('non_empty')
    end

    it 'should use cookbooks path' do
      RightScale::DevState.use_cookbooks_path?.should be_true
    end

    it 'should not download cookbooks' do
      RightScale::DevState.download_cookbooks?.should be_false
    end

    it 'should have a cookbooks path' do
      RightScale::DevState.cookbooks_path.should == [ 'some_path' ]
    end
  end

  shared_examples_for "has a breakpoint tag" do
    before :each do
      RightScale::InstanceState.startup_tags = RightScale::InstanceState.startup_tags << 'rs_agent_dev:break_point=some_recipe'
    end

    it 'should have a breakpoint' do
      RightScale::DevState.breakpoint.should == 'some_recipe'
    end
  end

  shared_examples_for "has instance state settings" do
    context "machine has no rs_agent_dev tags" do
      before :each do
        RightScale::InstanceState.startup_tags = [ 'some_tag', 'some:machine=tag' ]
      end

      it_should_behave_like "dev state is disabled"
      it_should_behave_like "nothing is set"

      context "after cookbooks are downloaded" do
        before :each do
          flexmock(RightScale::JsonUtilities).should_receive(:write_json).never
          RightScale::DevState.has_downloaded_cookbooks = true
        end

        it 'downloaded cookbooks flag should be set' do
          RightScale::DevState.has_downloaded_cookbooks?.should be_true
        end

        it 'should always download cookbooks' do
          RightScale::DevState.download_cookbooks?.should be_true
        end

        it 'should not persist the download state' do
          # reinitialize should load from the state file
          RightScale::DevState.reset
          RightScale::DevState.has_downloaded_cookbooks?.should == @expected_initial_has_downloaded_value
        end
      end
    end

    context "machine has at least one rs_agent_dev prefixed tag" do
      before :each do
        RightScale::InstanceState.startup_tags = RightScale::InstanceState.startup_tags << 'rs_agent_dev:some_tag=some_value'
      end

      it_should_behave_like "dev state is enabled"
      it_should_behave_like "nothing is set"
    end

    context "machine has a cookbooks_path tag that references an invalid path" do
      before :each do
        RightScale::InstanceState.startup_tags = RightScale::InstanceState.startup_tags << 'rs_agent_dev:cookbooks_path=some_invalid_path'

        flexmock(File).should_receive(:directory?).with('some_invalid_path').and_return(false)
      end

      it_should_behave_like "dev state is enabled"
      it_should_behave_like "has no cookbooks path"
      it 'should have a cookbooks path' do
        RightScale::DevState.cookbooks_path.should == [ 'some_invalid_path' ]
      end
    end

    context "machine has a cookbooks_path tag that references an empty path" do
      before :each do
        RightScale::InstanceState.startup_tags = RightScale::InstanceState.startup_tags << 'rs_agent_dev:cookbooks_path=some_empty_path'

        flexmock(File).should_receive(:directory?).with('some_empty_path').and_return(true)
        flexmock(Dir).should_receive(:entries).with('some_empty_path').and_return(['.','..'])
      end

      it_should_behave_like "dev state is enabled"
      it_should_behave_like "has no cookbooks path"
      it 'should have a cookbooks path' do
        RightScale::DevState.cookbooks_path.should == [ 'some_empty_path' ]
      end
    end

    context "machine has a cookbooks_path tag that references a valid path" do
      it_should_behave_like "dev state is enabled"
      it_should_behave_like "has a valid cookbooks path"
    end

    context "machine has a break_point tag" do
      it_should_behave_like "dev state is enabled"
      it_should_behave_like "has a breakpoint tag"
    end

    context "machine has download_cookbooks_once=true tag" do
      before :each do
        RightScale::InstanceState.startup_tags = RightScale::InstanceState.startup_tags << 'rs_agent_dev:download_cookbooks_once=true'
      end

      it_should_behave_like "dev state is enabled"
      it 'downloaded cookbooks should be initialized' do
        RightScale::DevState.has_downloaded_cookbooks?.should == @expected_initial_has_downloaded_value
      end

      context "after cookbooks are downloaded" do
        before :each do
          RightScale::DevState.has_downloaded_cookbooks = true
        end

        it 'downloaded cookbooks flag should be set' do
          RightScale::DevState.has_downloaded_cookbooks?.should be_true
        end

        it 'should not download cookbooks again' do
          RightScale::DevState.download_cookbooks?.should be_false
        end

        it 'should persist the download state' do
          # reinitialize should load from the state file
          RightScale::DevState.reset
          RightScale::DevState.has_downloaded_cookbooks?.should be_true
        end
      end
    end
  end

  context "initialized without state file (state has never been persisted)" do
    before :each do
      @expected_initial_has_downloaded_value = false
    end

    it_should_behave_like "has instance state settings"
  end

  context "initialized from empty state" do
    before :each do
      @expected_initial_has_downloaded_value = false
      RightScale::JsonUtilities::write_json(RightScale::DevState::STATE_FILE, {})
    end

    it_should_behave_like "has instance state settings"
  end

  context "initialized from state file with downloaded flag set to false" do
    before :each do
      @expected_initial_has_downloaded_value = false
      RightScale::JsonUtilities::write_json(RightScale::DevState::STATE_FILE, {"has_downloaded_cookbooks"=>false})
    end

    it_should_behave_like "has instance state settings"
  end

  context "initialized from state file with downloaded flag set to true" do
    before :each do
      @expected_initial_has_downloaded_value = true
      RightScale::JsonUtilities::write_json(RightScale::DevState::STATE_FILE, {"has_downloaded_cookbooks"=>true})
    end

    it_should_behave_like "has instance state settings"
  end

end
