#
# Copyright (c) 2011 RightScale Inc
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

describe RightScale::CookState do

  include RightScale::SpecHelpers

  # monkey patch CookState so we can reset singleton state during the test
  module RightScale
    class CookState
      def self.reset
        @@initialized = false
      end
    end
  end

  before :each do
    setup_state

    # re-initialize dev state
    FileUtils.rm_f(RightScale::CookState::STATE_FILE)
    RightScale::CookState.reset
  end

  shared_examples_for 'when the instance has download_cookbooks_once=true tag' do
    context 'the instance has download_cookbooks_once=true tag' do
      before(:each) do
        # tags can only exist in CookState if persisted in cook state file
        File.exists?(RightScale::CookState::STATE_FILE).should be_true

        current_state = RightScale::JsonUtilities::read_json(RightScale::CookState::STATE_FILE)
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, current_state.merge({"startup_tags"=>['rs_agent_dev:download_cookbooks_once=true']}))
      end

      it 'dev state should be enabled' do
        RightScale::CookState.dev_mode_enabled?.should be_true
      end

      context 'before cookbooks are downloaded' do
        it 'should download cookbooks' do
          RightScale::CookState.download_cookbooks?.should == @should_initially_download_cookbooks
        end

        context 'after cookbooks have been downloaded' do
          before(:each) do
            RightScale::CookState.has_downloaded_cookbooks = true
          end

          it 'should not download cookbooks' do
            RightScale::CookState.download_cookbooks?.should be_false
          end
        end
      end
    end
  end

  shared_examples_for 'when the instance does not have a download_cookbooks_once=true tag' do
    context 'the instance does not have a download_cookbooks_once=true tag' do
      before(:each) do
        if File.exists?(RightScale::CookState::STATE_FILE)
          current_state = RightScale::JsonUtilities::read_json(RightScale::CookState::STATE_FILE)
          unless current_state.empty?
            RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, current_state.merge({"startup_tags"=>[]}))
          end
        end
      end

      context 'before cookbooks are downloaded' do
        it 'downloaded cookbooks flag should not be set' do
          RightScale::CookState.has_downloaded_cookbooks?.should == @initial_has_downloaded_cookbooks
        end

        context 'after cookbooks have been downloaded' do
          before :each do
            RightScale::CookState.has_downloaded_cookbooks = true
          end

          it 'downloaded cookbooks flag should be set' do
            RightScale::CookState.has_downloaded_cookbooks?.should be_true
          end

          it 'should download cookbooks again' do
            RightScale::CookState.download_cookbooks?.should be_true
          end
        end
      end
    end
  end

  context 'has_downloaded_cookbooks?' do
    context 'when cook state has never been persisted' do
      before(:each) do
        @initial_has_downloaded_cookbooks = false
        @should_initially_download_cookbooks = true
        File.exists?(RightScale::CookState::STATE_FILE).should be_false
      end

      it_should_behave_like 'when the instance does not have a download_cookbooks_once=true tag'
    end

    context 'when persisted cook state is empty' do
      before(:each) do
        @initial_has_downloaded_cookbooks = false
        @should_initially_download_cookbooks = true
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {})
      end

      it_should_behave_like 'when the instance does not have a download_cookbooks_once=true tag'
    end

    context 'when has_downloaded_cookbooks is initialized to false' do
      before(:each) do
        @initial_has_downloaded_cookbooks = false
        @should_initially_download_cookbooks = true
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"has_downloaded_cookbooks"=>false})
      end

      it_should_behave_like 'when the instance does not have a download_cookbooks_once=true tag'
      it_should_behave_like 'when the instance has download_cookbooks_once=true tag'
    end

    context 'when has_downloaded_cookbooks is initialized to true' do
      before(:each) do
        @initial_has_downloaded_cookbooks = true
        @should_initially_download_cookbooks = false
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"has_downloaded_cookbooks"=>true})
      end

      it_should_behave_like 'when the instance does not have a download_cookbooks_once=true tag'
      it_should_behave_like 'when the instance has download_cookbooks_once=true tag'
    end
  end

  context 'rebooting?' do
    context 'when reboot flag is set' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"reboot"=>true})
      end

      it 'should be rebooting' do
        RightScale::CookState.reboot?.should be_true
      end
    end

    context 'when reboot flag is not set' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"reboot"=>false})
      end

      it 'should not be rebooting' do
        RightScale::CookState.reboot?.should be_false
      end
    end
  end

  context 'dev mode tags' do
    context 'when the instance has tags, but no dev mode tags' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"startup_tags"=>['some_tag', 'some:machine=tag']})
      end

      it 'dev state should not be enabled' do
        RightScale::CookState.dev_mode_enabled?.should be_false
      end
    end

    context 'when the instance has a coobook_path tag' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"startup_tags"=>['rs_agent_dev:cookbooks_path=some_path']})
      end

      context 'but cookbook path does not exist' do
        before(:each) do
          flexmock(File).should_receive(:directory?).with('some_path').and_return(false)
        end

        it 'dev state should be enabled' do
          RightScale::CookState.dev_mode_enabled?.should be_true
        end

        it 'should not use the dev cookbooks' do
          RightScale::CookState.use_cookbooks_path?.should be_false
        end

        it 'should download cookbooks' do
          RightScale::CookState.download_cookbooks?.should be_true
        end

        it 'should have a cookbooks path' do
          RightScale::CookState.cookbooks_path.should == ['some_path']
        end
      end

      context 'and cookbook path exists' do
        before(:each) do
          flexmock(File).should_receive(:directory?).with('some_path').and_return(true)
        end

        context 'and cookbook directory is not empty' do
          before(:each) do
            flexmock(Dir).should_receive(:entries).with('some_path').and_return('non_empty')
          end

          it 'dev state should be enabled' do
            RightScale::CookState.dev_mode_enabled?.should be_true
          end

          it 'should use the dev cookbooks' do
            RightScale::CookState.use_cookbooks_path?.should be_true
          end

          it 'should not download cookbooks' do
            RightScale::CookState.download_cookbooks?.should be_false
          end

          it 'should have a cookbooks path' do
            RightScale::CookState.cookbooks_path.should == ['some_path']
          end
        end

        context 'but cookbook directory is empty' do
          before(:each) do
            flexmock(Dir).should_receive(:entries).with('some_path').and_return(['.', '..'])
          end

          it 'dev state should be enabled' do
            RightScale::CookState.dev_mode_enabled?.should be_true
          end

          it 'should not use the dev cookbooks' do
            RightScale::CookState.use_cookbooks_path?.should be_false
          end

          it 'should download cookbooks' do
            RightScale::CookState.download_cookbooks?.should be_true
          end

          it 'should have a cookbooks path' do
            RightScale::CookState.cookbooks_path.should == ['some_path']
          end
        end
      end

    end

    context 'when the instance has a breakpoint tag' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"startup_tags"=>['rs_agent_dev:break_point=some_recipe']})
      end

      it 'dev state should be enabled' do
        RightScale::CookState.dev_mode_enabled?.should be_true
      end

      it 'should have a breakpoint' do
        RightScale::CookState.breakpoint.should == 'some_recipe'
      end
    end

    context 'when the instance has at least one dev tag' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {"startup_tags"=>['some:machine=tag', 'rs_agent_dev:break_point=some_recipe']})
      end

      it 'dev state should be enabled' do
        RightScale::CookState.dev_mode_enabled?.should be_true
      end
    end
  end

  context 'updating' do
    before(:each) do
      @mock_instance_state = flexmock('mock instance state', {:reboot? => true, :startup_tags => ['some:machine=value_one', 'rs_agent_dev:download_cookbooks_once=true']})
    end

    context 'when updating and cook state has never been persisted' do
      before(:each) do
        File.exists?(RightScale::CookState::STATE_FILE).should be_false

        # update cook state, then reset to force loading of new state
        RightScale::CookState.has_downloaded_cookbooks?.should be_false
        RightScale::CookState.download_once?.should be_false
        RightScale::CookState.reboot?.should be_false
        RightScale::CookState.update(@mock_instance_state)
        RightScale::CookState.reset
      end

      it 'should override the reboot value' do
        RightScale::CookState.reboot?.should be_true
      end

      it 'should override the startup_tags value' do
        RightScale::CookState.download_once?.should be_true
      end

      it 'should not change the has_downloaded_cookbooks value' do
        RightScale::CookState.has_downloaded_cookbooks?.should be_false
      end
    end

    context 'when updating and cook state and persisted cook state is empty' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {})
        File.exists?(RightScale::CookState::STATE_FILE).should be_true

        # update cook state, then reset to force loading of new state
        RightScale::CookState.has_downloaded_cookbooks?.should be_false
        RightScale::CookState.download_once?.should be_false
        RightScale::CookState.reboot?.should be_false
        RightScale::CookState.update(@mock_instance_state)
        RightScale::CookState.reset
      end

      it 'should override the reboot value' do
        RightScale::CookState.reboot?.should be_true
      end

      it 'should override the startup_tags value' do
        RightScale::CookState.download_once?.should be_true
      end

      it 'should not change the has_downloaded_cookbooks value' do
        RightScale::CookState.has_downloaded_cookbooks?.should be_false
      end
    end

    context 'when updating and cook state has been persisted with existing state' do
      before(:each) do
        RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, {'has_downloaded_cookbooks' => true,
                                                                                  'reboot' => false,
                                                                                  'startup_tags' => ['some:initial=tag']})
        File.exists?(RightScale::CookState::STATE_FILE).should be_true

        # update cook state, then reset to force loading of new state
        RightScale::CookState.has_downloaded_cookbooks?.should be_true
        RightScale::CookState.download_once?.should be_false
        RightScale::CookState.reboot?.should be_false
        RightScale::CookState.update(@mock_instance_state)
        RightScale::CookState.reset
      end

      it 'should override the reboot value' do
        RightScale::CookState.reboot?.should be_true
      end

      it 'should override the startup_tags value' do
        RightScale::CookState.download_once?.should be_true
      end

      it 'should not change the has_downloaded_cookbooks value' do
        RightScale::CookState.has_downloaded_cookbooks?.should be_true
      end
    end
  end
end
