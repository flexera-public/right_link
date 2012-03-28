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
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'bundle_runner'))

module RightScale
  shared_examples_for 'command line argument' do
    it 'short form' do
      subject.parse_args([short_name, value])[key].should == expected_value
    end
    it 'long form' do
      subject.parse_args([long_name, value])[key] == value
    end
    it 'short and long form should match' do
      subject.parse_args([short_name, value])[key].should == subject.parse_args([long_name, value])[key]
    end
  end

  describe BundleRunner do
    context 'version' do
      it 'reports RightLink version from gemspec' do
        class BundleRunner
          def test_version
            version
          end
        end
        
        subject.test_version.should match /rs_run_right_script & rs_run_recipe \d+\.\d+\.?\d* - RightLink's bundle runner \(c\) 2011 RightScale/
      end

      context 'identity option' do
        let(:short_name)    {'-i'}
        let(:long_name)     {'--identity'}
        let(:key)           {:id}
        let(:value)         {'rs-instance-1-1'}
        let(:expected_value){value}
        it_should_behave_like 'command line argument'
      end

      context 'config dir option' do
        let(:short_name)    {'-c'}
        let(:long_name)     {'--cfg-dir'}
        let(:key)           {:cfg_dir}
        let(:value)         {'/some/dir'}
        let(:expected_value){value}
        it_should_behave_like 'command line argument'
      end

      context 'policy option' do
        let(:short_name)    {'-P'}
        let(:long_name)     {'--policy'}
        let(:key)           {:policy}
        let(:value)         {'oh_by_the_way_policy_name'}
        let(:expected_value){value}
        it_should_behave_like 'command line argument'
      end

      context 'thread name option' do
        let(:short_name)    {'-t'}
        let(:long_name)     {'--thread'}
        let(:key)           {:thread}
        let(:value)         {'oh_by_the_way_thread_name'}
        let(:expected_value){value}
        it_should_behave_like 'command line argument'
      end

      context 'verbose option' do
        let(:short_name)    {'-v'}
        let(:long_name)     {'--verbose'}
        let(:key)           {:verbose}
        let(:value)         {nil}
        let(:expected_value){true}
        it_should_behave_like 'command line argument'
      end

      context 'name option' do
        let(:short_name)    {'-n'}
        let(:long_name)     {'--name'}
        let(:key)           {:name}
        let(:value)         {'foo'}
        let(:expected_value){value}
        it_should_behave_like 'command line argument'

        context 'when --identity is also provided' do
          it 'should ignore the identity value for short version' do
            pending 'need to handle ordering of command line parameters so this works as designed.'
            subject.parse_args([short_name, value, '-i', 'rs-instance-1-1'])[key].should be_nil
          end
          it 'should ignore the identity value for short version' do
            pending 'need to handle ordering of command line parameters so this works as designed.'
            subject.parse_args([long_name, value, '-i', 'rs-instance-1-1'])[key].should be_nil
          end
          it 'id value should be in the result' do
            subject.parse_args([long_name, value, '-i', 'rs-instance-1-1'])[:id].should == "rs-instance-1-1"
          end
        end
      end

      context 'parameter option' do
        let(:short_name)      {'-p'}
        let(:long_name)       {'--parameter'}
        let(:key)             {:parameters}
        let(:value)           {'DB_PASSWORD=text:mypass'}
        let(:expected_value)  {{'DB_PASSWORD' => 'text:mypass'}}
        it_should_behave_like 'command line argument'

        it 'should raise if a value is not in the correct format' do
          lambda { subject.parse_args(['-p', 'DB_PASSWORD=foo']) }.should raise_error(SystemExit)
        end

        context 'with multiple parameter options' do
          let(:values)        {['DB_PASSWORD=text:mypass', 'DB_USER=text:admin', 'DB_HOST=text:localhost@localhost.com']}
          let(:args)          {values.inject([]) { |result, v| result << short_name << v; result }}
          let(:expected_value){{'DB_PASSWORD' => 'text:mypass',
                                'DB_USER' => 'text:admin',
                                'DB_HOST' => 'text:localhost@localhost.com'}}

          it 'should add all parameters to the result' do
            subject.parse_args(args)[key].should == expected_value
          end
          it 'should overwrite values if a parameter with the same is repeated' do
            subject.parse_args(args + [short_name, 'DB_PASSWORD=text:newpass'])[key]['DB_PASSWORD'] == 'text:newpass'
          end
        end
      end

      context 'tags option' do
        let(:short_name)    {'-r'}
        let(:long_name)     {'--recipient_tags'}
        let(:key)           {:tags}
        let(:value)         {'rs_agent_dev:package=foo'}
        let(:expected_value){[value]}
        it_should_behave_like 'command line argument'

        it 'should parse multiple tags' do
          subject.parse_args([short_name, 'tag1,tag2,tag3'])[key] == ['tag1','tag2','tag3']
        end
      end

      context 'tags option' do
        let(:short_name)    {'-s'}
        let(:long_name)     {'--scope'}
        let(:key)           {:scope}

        context 'single scope' do
          let(:value)         {'single'}
          let(:expected_value){:any}
          it_should_behave_like 'command line argument'
        end

        context 'all scope' do
          let(:value)         {'all'}
          let(:expected_value){:all}
          it_should_behave_like 'command line argument'
        end

        it 'should raise given any value other than "single" or "all"' do
          lambda { subject.parse_args([short_name, 'foo']) }.should raise_error(SystemExit)
        end
      end

      context 'json option' do
        let(:short_name)    {'-j'}
        let(:long_name)     {'--json'}
        let(:key)           {:json}
        let(:json_file)     {File.join(Dir.tmpdir, "bundle_runner_spec-#{rand(2**10)}", 'test.json')}
        let(:value)         {json_file}
        let(:expected_value){{'foo' => 'bar', 'baz' => {'fourtytwo' => 42}}.to_json}

        before do
          FileUtils.mkdir_p(File.dirname(json_file))
          File.open(json_file, 'w') { |f| f.write expected_value}
        end

        after   {FileUtils.rm_rf(File.dirname(json_file))}

        it_should_behave_like 'command line argument'

        context 'when json file does not exist' do
          it 'should raise and report' do
            lambda { subject.parse_args([short_name, 'foo']) }.should raise_error(SystemExit)
          end
        end

        context 'when file does not contain json' do
          before do
            File.open(json_file, 'w') { |f| f.puts "this is not a json\nstring"}
          end

          it 'should raise and report' do
            pending 'Until error message/state matches the code.  Code is not currently ensuring json content is correct.'
            lambda { subject.parse_args([short_name, value]) }.should raise_error(SystemExit)
          end
        end
      end
    end
  end
end