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
  describe BundleRunner do
    def send_command(args, bundle_type, forwarder_opts,timeout=BundleRunner::DEFAULT_TIMEOUT, verbose=false)
      flexmock(AgentConfig).should_receive(:agent_options).and_return({:listen_port => 123})
      client = flexmock("CommandClient")
      flexmock(CommandClient).should_receive(:new).and_return(client)
      cmd = {:options => forwarder_opts }
      cmd[:name] = bundle_type == :right_script ? 'run_right_script' : 'run_recipe'
      client.should_receive(:send_command).with( cmd, verbose, timeout, Proc).once
      run_bundle_runner(args, bundle_type)
    end

    def run_bundle_runner(argv, bundle_type)
      replace_argv(argv)
      opts = subject.parse_args
      opts[:bundle_type] = bundle_type
      subject.run(opts)
      return 0
    rescue SystemExit => e
      return e.status
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
      flexmock(subject).should_receive(:print).and_return { |message| @output << message; true }
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
          it 'should ignore the identity value for long version' do
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

        it 'should fail if a value is not in the correct format' do
          p = 'DB_PASSWORD=foo'
          flexmock(subject).should_receive(:fail).with("Invalid parameter definition '#{p}', should be of the form 'name=type:value'")
          subject.parse_args(['-p', p])
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

        it 'should fail given any value other than "single" or "all"' do
          flexmock(subject).should_receive(:fail).with("Invalid scope definition 'foo', should be either 'single' or 'all'")
          subject.parse_args([short_name, 'foo']) 
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
          it 'should fail' do
            flexmock(subject).should_receive(:fail).with("Invalid JSON filename 'foo'")
            lambda { subject.parse_args([short_name, 'foo']) }
          end
        end

        context 'when file does not contain json' do
          before do
            File.open(json_file, 'w') { |f| f.puts "this is not a json\nstring"}
          end

          it 'should fail' do
            pending 'Until error message/state matches the code.  Code is not currently ensuring json content is correct.'
            lambda { subject.parse_args([short_name, value]) }.should raise_error(SystemExit)
          end
        end
      end

    context 'rs_run_right_script --version' do
      it 'reports RightLink version from gemspec' do
        run_bundle_runner('--version', :right_script)
        @output.join('\n').should match /rs_run_right_script & rs_run_recipe \d+\.\d+\.?\d* - RightLink's bundle runner \(c\) 2011 RightScale/
      end
    end

    context 'rs_run_recipe --help' do
      it 'should show usage info' do
        usage = Usage.scan(File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'bundle_runner.rb')))
        run_bundle_runner('--help', :right_script)
        @output.join('\n').should include(usage)
      end
    end

    context 'rs_run_recipe --identity 12' do
      it 'should run recipe with id 12' do
        send_command(['--identity', '12'], :recipe, {
          :recipe_id => "12",
          :json => nil
        })
      end
    end

    context 'rs_run_recipe -n nginx -j attribs.js' do
      let(:json_file)     {File.join(Dir.tmpdir, "bundle_runner_spec-#{rand(2**10)}", 'attribs.json')}
      let(:value)         {json_file}
      let(:expected_value){{'foo' => 'bar', 'baz' => {'fourtytwo' => 42}}.to_json}

      before do
        FileUtils.mkdir_p(File.dirname(json_file))
        File.open(json_file, 'w') { |f| f.write expected_value}
      end

      after   {FileUtils.rm_rf(File.dirname(json_file))}

      it 'should run recipe \'nginx\' using given JSON attributes file' do
        send_command(['-n', 'nginx', '-j', json_file], :recipe, {
          :recipe => 'nginx',
          :json => expected_value
        })
      end
    end

    context 'rs_run_right_script -i 14 -p APPLICATION=text:Mephisto' do
      it 'should run RightScript with id 14 and override input \'APPLICATION\' with value \'Mephisto\'' do
        send_command('-i 14 -p APPLICATION=text:Mephisto'.split, :right_script, {
          :right_script_id => "14", 
          :arguments => { "APPLICATION" => "text:Mephisto" } 
        })
      end
    end

    context 'rs_run_recipe -i 14 -r "tag1 tag2" -s single' do
      it 'should run recipe with id 14 on a single server with tags: tag1, tag2' do
        send_command(['-i', '14', '-r', 'tag1 tag2', '-s', 'single'], :recipe, {
          :tags => ["tag1", "tag2"],
          :recipe_id => "14",
          :selector => :any,
          :json => nil
        })
      end
    end

    context 'rs_run_recipe -i 14 -r "tag1 tag2"' do
      it 'should run recipe with id 14 on all servers with tags: tag1, tag2' do
        send_command(['-i', '14', '-r', 'tag1 tag2'], :recipe, {
          :tags => ["tag1", "tag2"],
          :recipe_id => "14",
          :selector => :all,
          :json => nil
        })
      end
    end

    context 'rs_run_recipe -i 14 --policy SWAG' do
      it 'should run recipe with id 14 auditing on SWAG policy' do
        send_command('-i 14 --policy SWAG'.split, :recipe, {
          :recipe_id => "14",
          :json => nil,
          :policy => "SWAG"
        })
      end
    end

    context 'rs_run_recipe -i 14 --thread thread123' do
      it 'should run recipe with id 14 on thread123 thread' do
        send_command('-i 14 --thread thread123'.split, :recipe, {
          :recipe_id => "14",
          :json => nil,
          :thread => "thread123"
        })
      end
    end

    context 'rs_run_recipe -i 14 -a 100' do
      it 'should run recipe with id 14 and 100 seconds between audits' do
        send_command('-i 14 -a 100'.split, :recipe, {
          :recipe_id => "14",
          :json => nil,
          :audit_period => 100
        })
      end
    end

    context 'rs_run_recipe -a 1000' do
      it 'should fail because of missing identity or name argument' do
        flexmock(subject).should_receive(:fail).with('Missing identity or name argument', true)
        send_command('-a 1000'.split, :recipe, {
          :audit_period => 1000,
          :json => nil
        })
      end
    end

    context 'rs_run_recipe -i 14 --thread THreaD123' do
      it 'should fail because of invalid thread name' do
        flexmock(subject).should_receive(:fail).with('Invalid thread name THreaD123', true)
        send_command('-i 14 --thread THreaD123'.split, :recipe, {
          :recipe_id => "14",
          :json => nil,
          :thread => "THreaD123"
        })
      end
    end

    context 'rs_run_recipe -i 14 -c /etc/etc' do
      it 'should change set directory containing configuration for all agents to /etc/etc' do
        flexmock(AgentConfig).should_receive(:cfg_dir=).with('/etc/etc')
        send_command('-i 14 -c /etc/etc'.split, :recipe, {
          :recipe_id => "14",
          :json => nil
        })
      end
    end


  end
end
