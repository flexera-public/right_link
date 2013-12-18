# Copyright (c) 2013 RightScale, Inc, All Rights Reserved Worldwide.
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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'config_controller'))

module RightScale
  describe RightLinkConfigController do
    def run_config_controller(args)
      replace_argv(args)
      subject.control(subject.parse_args)
      return 0
    rescue SystemExit => e
      return e.status
    end

    before(:all) do
      # preserve old ARGV for posterity (although it's unlikely that anything
      # would consume it after startup).
      @old_argv = ARGV
      @test_data = { "motd"=>{"update"=>false},
                    "decommission"=>{"timeout"=>100},
                    "package_repositories"=>{"freeze"=>true} }
      @config_yaml_file = File.normalize_path(File.join(RightScale::Platform.filesystem.right_link_static_state_dir, 'features.yml'))
    end

    after(:all) do
      # restore old ARGV
      replace_argv(@old_argv)
      @error = nil
      @output = nil
    end

    before(:each) do
      @output = []
      flexmock(subject).should_receive(:puts).and_return { |message| @output << message; true }
      flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
    end

    context 'list option' do
      let(:short_name)      {'-l'}
      let(:long_name)       {'--list'}
      let(:key)             {:action}
      let(:value)           {''}
      let(:expected_value)  {:list}
      it_should_behave_like 'command line argument'
    end

    context 'set option' do
      let(:short_name)      {'-s'}
      let(:long_name)       {'--set'}
      let(:key)             {:action}
      let(:value)           {['decommission_timeout', '180']}
      let(:expected_value)  {:set}
      it_should_behave_like 'command line argument'
    end

    context 'get option' do
      let(:short_name)      {'-g'}
      let(:long_name)       {'--get'}
      let(:key)             {:action}
      let(:value)           {'decommission_timeout'}
      let(:expected_value)  {:get}
      it_should_behave_like 'command line argument'
    end

    context 'rs_config --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'config_controller.rb')))
        run_config_controller('--help')
        @output.join('\n').should include usage
      end
    end

    context 'rs_config --version' do
      it 'should report RightLink version from gemspec' do
        run_config_controller('--version')
        @output.join('\n').should match /rs_config \d+\.\d+\.?\d* - RightLink's configuration manager\(c\) \d+ RightScale/
      end
    end

    context 'rs_config' do
      it 'should fail because no action was specified' do
        flexmock(subject).should_receive(:fail).with("No action specified").and_raise(SystemExit)
        run_config_controller([])
      end
    end

    context 'rs_config --list' do
      it 'should list all features with values from config file' do
        flexmock(File).should_receive(:exists?).with(@config_yaml_file).and_return(true)
        flexmock(YAML).should_receive(:load_file).and_return(@test_data)
        run_config_controller('--list')
        @output.join('\n').should include @test_data.to_yaml
      end
    end

    context 'rs_config --get decommission_timeout' do
      it 'should outputs the value of the given feature' do
        flexmock(File).should_receive(:exists?).with(@config_yaml_file).and_return(true)
        flexmock(YAML).should_receive(:load_file).and_return(@test_data)
        run_config_controller(['--get', 'decommission_timeout'])
        @output.join('\n').should include @test_data['decommission']['timeout'].to_s
      end
    end

    context 'rs_config --get UNSUPPORTED' do
      it 'should fail because unsupported feature was specified' do
        flexmock(subject).should_receive(:fail).with("Unsupported feature 'UNSUPPORTED'").and_raise(SystemExit)
        run_config_controller(['--get', 'UNSUPPORTED'])
      end
    end

    context 'rs_config --set decommission_timeout 200' do
      it 'shout set specifed feature to provided value' do
        flexmock(File).should_receive(:exists?).with(@config_yaml_file).and_return(true)
        flexmock(File).should_receive(:open).with(@config_yaml_file, "w", Proc).and_return(true)
        flexmock(YAML).should_receive(:load_file).and_return(@test_data)
        value = 200
        run_config_controller(['--set', 'decommission_timeout', value.to_s])
        @test_data['decommission']['timeout'] = value
        run_config_controller(['--get', 'decommission_timeout'])
        @output.join('\n').should include value.to_s
      end
    end

    context 'rs_config --set decommission_timeout INVALID' do
      it 'should fail because invalid value was specified' do
        flexmock(subject).should_receive(:fail).with("Invalid value 'INVALID' for decommission_timeout").and_raise(SystemExit)
        run_config_controller(['--set', 'decommission_timeout', 'INVALID'])
      end
    end

  end
end
