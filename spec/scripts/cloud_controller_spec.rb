# Copyright (c) 2009-2011 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'cloud_controller'))

module RightScale

  describe CloudController do
    def run_cloud_controller(args)
      replace_argv(args)
      subject.control(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    def send_command(args, name, action, parameters=[])
        instance = flexmock("instance")
        cloud = flexmock("cloud")
        flexmock(CloudFactory).should_receive(:instance).and_return(instance)
        instance.should_receive(:create).with(name, Hash).and_return(cloud)
        cloud.should_receive(:respond_to?).with(action).and_return(true)
        cloud.should_receive(:send).with(action, *parameters).and_return(:output => "OK")
        #flexmock(subject).should_receive(:exit).with(1).never
        run_cloud_controller(args)
    end

    before(:all) do
      # preserve old ARGV for posterity (although it's unlikely that anything
      # would consume it after startup).
      @old_argv = ARGV
    end

    after(:all) do
      # restore old ARGV
      replace_argv(@old_argv)
      @error = nil
      @output = nil
    end

    before(:each) do
      @error = []
      @output = []
      flexmock(subject).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(subject).should_receive(:print).and_return { |message| @output << message; true }
    end

    context 'action option' do
      let(:short_name)    {'-a'}
      let(:long_name)     {'--action'}
      let(:key)           {:action}
      let(:value)         {'write_metadata'}
      let(:expected_value){'write_metadata'}
      it_should_behave_like 'command line argument'
    end

    context 'name option' do
      let(:short_name)    {'-n'}
      let(:long_name)     {'--name'}
      let(:key)           {:name}
      let(:value)         {'ec2'}
      let(:expected_value){'ec2'}
      it_should_behave_like 'command line argument'
    end

    context 'parameters option' do
      let(:short_name)    {'-p'}
      let(:long_name)     {'--parameters'}
      let(:key)           {:parameters}
      let(:value)         {'["param1","param2"]'}
      let(:expected_value){['param1', 'param2']}
      it_should_behave_like 'command line argument'
    end

    context 'only-if option' do
      let(:short_name)    {'-o'}
      let(:long_name)     {'--only-if'}
      let(:key)           {:only_if}
      let(:value)         {''}
      let(:expected_value){true}
      it_should_behave_like 'command line argument'
    end

    context 'cloud --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'cloud_controller.rb')))
        run_cloud_controller('--help')
        @output.join('\n').should include usage 
      end
    end
    
    context 'cloud' do
      it 'should fail because no action was specified' do
        flexmock(subject).should_receive(:fail).with("No action specified on the command line.").and_raise(SystemExit)
        run_cloud_controller([])
      end
    end

    context 'cloud --action=write_metadata' do
      it 'should write cloud and user metadata to cache directory using default cloud' do
        send_command('--action=write_metadata',
                     CloudFactory::UNKNOWN_CLOUD_NAME.to_s,
                     :write_metadata)
      end
    end

    context 'cloud --name=ec2 --action=write_user_metadata' do
      it 'should write user metadata only to cache directory using named ec2 cloud' do
        send_command('--name=ec2 --action=write_user_metadata'.split,
                     "ec2",
                     :write_user_metadata)
      end
    end

    context 'cloud --action=read_user_metadata --parameters=dictionary_metadata_writer' do
      it 'should read default cloud user metadata in dictionary format (metadata is output)' do send_command('--action=read_user_metadata --parameters=dictionary_metadata_writer'.split,
                     CloudFactory::UNKNOWN_CLOUD_NAME.to_s,
                     :read_user_metadata, 
                    ["dictionary_metadata_writer"])
      end
    end

    def wrong_action_setup
      name = CloudFactory::UNKNOWN_CLOUD_NAME.to_s
      instance = flexmock("instance")
      cloud = flexmock("cloud")
      flexmock(CloudFactory).should_receive(:instance).and_return(instance)
      instance.should_receive(:create).with(name, Hash).and_return(cloud)
      cloud.should_receive(:respond_to?).with(:read_user_metadata).and_return(true)
      cloud.should_receive(:send).with(:read_user_metadata).and_return(:output => "OK")
      cloud.should_receive(:respond_to?).with(:WRONG_ACTION).and_return(false)
    end

    context 'cloud --action=read_user_metadata,WRONG_ACTION' do
      it 'should fail because of wrong action' do
        wrong_action_setup
        expect { run_cloud_controller('--action=read_user_metadata,WRONG_ACTION') }.to raise_error(ArgumentError)
      end
    end

    context 'cloud --action=read_user_metadata,WRONG_ACTION --only-if' do
      it 'should not fail because of wrong action' do
        wrong_action_setup
        run_cloud_controller("--action=read_user_metadata,WRONG_ACTION --only-if".split)
      end
    end
  end
end
