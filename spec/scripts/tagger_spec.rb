# Copyright (c) 2009-2012 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require 'tmpdir'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'tagger'))

module RightScale::TaggerSpec
  RS_INSTANCE_ID_1 = "rs-instance-abcd-123"
  RS_INSTANCE_ID_2 = "rs-instance-efgh-456"

  DEFAULT_QUERY_RESULT = {
    RS_INSTANCE_ID_1 => {
      "tags" => ["foo:bar=baz zab", "rs_login:state=restricted"]
    },
    RS_INSTANCE_ID_2 => {
      "tags" => ["bar:foo=baz zab",
                 "foo:bar=baz zab",
                 "rs_login:state=restricted",
                 "rs_monitoring:state=active",
                 "x:y=a b c:d=x y"]
    }
  }
end

describe RightScale::Tagger do

  # Runs the tagger and rescues expected exit calls.
  #
  # === Parameters
  # @param [Array, String] argv for command-line parser to consume
  #
  # === Return
  # @return [Fixnum] exit code or zero
  def run_tagger(argv)
    replace_argv(argv)
    flexmock(subject).should_receive(:fail_on_right_agent_is_not_running).and_return(true)
    flexmock(subject).should_receive(:check_privileges).and_return(true)
    subject.run(subject.parse_args)
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
    flexmock(subject).should_receive(:write_error).and_return { |message| @error << message; true }
    flexmock(subject).should_receive(:write_output).and_return { |message| @output << message; true }
    flexmock(STDERR).should_receive(:puts).and_return { |message| @error << message; true }
    flexmock(STDOUT).should_receive(:puts).and_return { |message| @output << message; true }
  end

  context 'list option' do
    let(:short_name)    {'-l'}
    let(:long_name)     {'--list'}
    let(:key)           {:action}
    let(:value)         {''}
    let(:expected_value){:get_tags}
    it_should_behave_like 'command line argument'
  end

  context 'add option' do
    let(:short_name)    {'-a'}
    let(:long_name)     {'--add'}
    let(:key)           {:action}
    let(:value)         {'tag'}
    let(:expected_value){:add_tag}
    it_should_behave_like 'command line argument'
  end

  context 'remove option' do
    let(:short_name)    {'-r'}
    let(:long_name)     {'--remove'}
    let(:key)           {:action}
    let(:value)         {'tag'}
    let(:expected_value){:remove_tag}
    it_should_behave_like 'command line argument'
  end

  context 'query option' do
    let(:short_name)    {'-q'}
    let(:long_name)     {'--query'}
    let(:key)           {:action}
    let(:value)         {'tag'}
    let(:expected_value){:query_tags}
    it_should_behave_like 'command line argument'
  end

  context 'verbose option' do
    let(:short_name)    {'-v'}
    let(:long_name)     {'--verbose'}
    let(:key)           {:verbose}
    let(:value)         {''}
    let(:expected_value){true}
    it_should_behave_like 'command line argument'
  end

  context 'die option' do
    let(:short_name)    {'-e'}
    let(:long_name)     {'--die'}
    let(:key)           {:die}
    let(:value)         {''}
    let(:expected_value){true}
    it_should_behave_like 'command line argument'
  end

  context 'format option' do
    let(:short_name)    {'-f'}
    let(:long_name)     {'--format'}
    let(:key)           {:format}
    let(:value)         {'yaml'}
    let(:expected_value){:yaml}
    it_should_behave_like 'command line argument'
  end

  context 'timeout option' do
    let(:short_name)    {'-t'}
    let(:long_name)     {'--timeout'}
    let(:key)           {:timeout}
    let(:value)         {'100'}
    let(:expected_value){100}
    it_should_behave_like 'command line argument'
  end

  context 'rs_tag --version' do
    it 'should report RightLink version from gemspec' do
      run_tagger('--version')
      @error.should == []
      @output.join("\n").should match /^rs_tag \d+\.\d+\.?\d* - RightLink's tagger \(c\) 2009-\d+ RightScale$/
    end
  end

  context 'rs_tag --list' do
    it 'should list known tags on the instance' do
      listing = ::RightScale::TaggerSpec::DEFAULT_QUERY_RESULT[ ::RightScale::TaggerSpec::RS_INSTANCE_ID_1 ]["tags"]
      flexmock(subject)
        .should_receive(:send_command)
        .with({ :name => :get_tags },false, 60)
        .once
        .and_return(listing)
      flexmock(subject).should_receive(:serialize_operation_result).never
      run_tagger(['-l'])
      @error.should == []
      @output.should == [JSON.pretty_generate(listing)]
    end
  end

  context 'rs_tag --query' do

    # Runs a successful tagger query and verifies output.
    #
    # === Parameters
    # @param [Array] tags
    # @param [Array, String] expected_tags for command client payload
    # @param [String] format (as json|yaml|text) for query result or nil
    # @param [String] expected_formatter for query result
    # @param [Hash] query_result or default
    def run_successful_query( tags,
                              expected_tags,
                              format=nil,
                              expected_formatter=JSON.method(:pretty_generate),
                              query_result=::RightScale::TaggerSpec::DEFAULT_QUERY_RESULT)
      expected_cmd = { :name => :query_tags, :tags => Array(expected_tags) }
      flexmock(subject).
        should_receive(:send_command).
        with(expected_cmd, false, 60).
        once.
        and_return('stuff')
      flexmock(subject).
        should_receive(:serialize_operation_result).
        with('stuff').
        once.
        and_return(::RightScale::OperationResult.success(query_result))
      argv = ['-q'] + tags
      argv << '-f' << format if format
      run_tagger(argv)
      @error.should == []
      @output.should == [expected_formatter.call(query_result)]
    end

    # Formatter for query format=text
    def text_formatter(query_result)
      query_result.keys.join(" ")
    end

    it 'should query instances with given tag in default JSON format' do
      run_successful_query(['foo:bar'], 'foo:bar')
    end

    it 'should query instances with given tag in requested JSON format' do
      run_successful_query(['foo:bar'], 'foo:bar', 'json')
    end

    it 'should query instances with given tag in requested TEXT format' do
      run_successful_query(['foo:bar'], 'foo:bar', 'text', method(:text_formatter))
    end

    it 'should query instances with given tag in requested YAML format' do
      run_successful_query(['foo:bar'], 'foo:bar', 'yaml', YAML.method(:dump))
    end

    it 'should fail to query instances with invalid format' do
      run_tagger(['-q', 'foo:bar', '-f', 'bogus']).should == 1
      @error.should == ["Unknown output format bogus\nUse --help for additional information"]
      @output.should == []
    end

    it 'should query instances with multiple tags delimited by spaces' do
      run_successful_query(['foo:bar','bar:foo'], ['foo:bar', 'bar:foo'])
    end

    it 'should query instances with a single tag whose value contains spaces' do
      run_successful_query(['foo:bar=baz zab'], 'foo:bar=baz zab')
    end

    it 'should query instances with a single tag containing ambiguous spaces and equals' do
      query_result = {
        ::RightScale::TaggerSpec::RS_INSTANCE_ID_2 =>
          ::RightScale::TaggerSpec::DEFAULT_QUERY_RESULT[ ::RightScale::TaggerSpec::RS_INSTANCE_ID_2 ]
      }
      run_successful_query(['x:y=a b c:d=x y'],
                           'x:y=a b c:d=x y',
                           'yaml',
                           YAML.method(:dump),
                           query_result)
    end
  end # rs_tag --query

  context 'rs_tag --add' do
    it 'should add or update a tag on the instance' do
      expected_cmd = { :name => :add_tag, :tag => 'x:y=z' }
      flexmock(subject).
        should_receive(:send_command).
        with(expected_cmd, false, 60).
        once.
        and_return('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(true))
      run_tagger(['-a', 'x:y=z'])
      @error.should == ["Successfully added tag x:y=z"]
      @output.should == []
    end

    it 'should dispaly error if empty value provided' do
      expected_cmd = { :name => :add_tag, :tag => '' }
      flexmock(subject).should_receive(:send_command).never
      run_tagger(['-a', ''])
      @error.should == ["Non-empty value required\nUse --help for additional information"]
      @output.should == []
    end
  end # rs_tag --add

  context 'rs_tag --remove' do
    it 'should remove a tag from the instance' do
      expected_cmd = { :name => :remove_tag, :tag => 'x:y' }
      flexmock(subject).
        should_receive(:send_command).
        with(expected_cmd, false, 60).
        once.
        and_return('stuff')
      flexmock(subject).
        should_receive(:serialize_operation_result).
        with('stuff').
        once.
        and_return(::RightScale::OperationResult.success(true))
      run_tagger(['-r', 'x:y'])
      @error.should == []
      @output.should == ["Request processed successfully"]
    end
    it 'should dispaly error if empty value provided' do
      expected_cmd = { :name => :remove_tag, :tag => '' }
      flexmock(subject).should_receive(:send_command).never
      run_tagger(['-r', ''])
      @error.should == ["Non-empty value required\nUse --help for additional information"]
      @output.should == []
    end
  end # rs_tag --remove
end # RightScale::Tagger
