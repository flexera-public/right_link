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
  QUERY_RESULT = {
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

  def replace_argv(new_argv)
    ::Object.send(:remove_const, :ARGV)  # suppress const redefinition warning
    ::Object.send(:const_set, :ARGV, Array(new_argv))
  end

  def run_tagger(argv)
    replace_argv(argv)
    subject.run(subject.parse_args)
    return 0
  rescue SystemExit => e
    return e.status
  end

  before(:all) do
    @old_argv = ARGV
  end

  after(:all) do
    replace_argv(@old_argv)
  end

  before(:each) do
    @error = []
    @output = []
    flexmock(subject).should_receive(:write_error).and_return { |message| @error << message; true }
    flexmock(subject).should_receive(:write_output).and_return { |message| @output << message; true }
  end

  after(:each) do
    @error = nil
    @output = nil
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
      listing = ::RightScale::TaggerSpec::QUERY_RESULT[ ::RightScale::TaggerSpec::RS_INSTANCE_ID_1 ]["tags"]
      flexmock(subject).should_receive(:send_command).with(
        { :name => :get_tags },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield(listing)
      flexmock(subject).should_receive(:serialize_operation_result).never
      run_tagger(['-l'])
      @error.should == []
      @output.should == [JSON.pretty_generate(listing)]
    end
  end

  context 'rs_tag --query' do
    it 'should query instances with given tag in default JSON format' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['foo:bar'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(::RightScale::TaggerSpec::QUERY_RESULT))
      run_tagger(['-q', 'foo:bar'])
      @error.should == []
      @output.should == [JSON.pretty_generate(::RightScale::TaggerSpec::QUERY_RESULT)]
    end

    it 'should query instances with given tag in requested JSON format' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['foo:bar'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(::RightScale::TaggerSpec::QUERY_RESULT))
      run_tagger(['-q', 'foo:bar', '-f', 'json'])
      @error.should == []
      @output.should == [JSON.pretty_generate(::RightScale::TaggerSpec::QUERY_RESULT)]
    end

    it 'should query instances with given tag in requested TEXT format' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['foo:bar'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(::RightScale::TaggerSpec::QUERY_RESULT))
      run_tagger(['-q', 'foo:bar', '-f', 'text'])
      @error.should == []
      @output.should == [::RightScale::TaggerSpec::QUERY_RESULT.keys.join(" ")]
    end

    it 'should query instances with given tag in requested YAML format' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['foo:bar'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(::RightScale::TaggerSpec::QUERY_RESULT))
      run_tagger(['-q', 'foo:bar', '-f', 'yaml'])
      @error.should == []
      @output.should == [YAML.dump(::RightScale::TaggerSpec::QUERY_RESULT)]
    end

    it 'should query instances with multiple tags delimited by spaces' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['foo:bar', 'bar:foo'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(::RightScale::TaggerSpec::QUERY_RESULT))
      run_tagger(['-q', 'foo:bar bar:foo'])
      @error.should == []
      @output.should == [JSON.pretty_generate(::RightScale::TaggerSpec::QUERY_RESULT)]
    end

    it 'should query instances with a single tag whose value contains spaces' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['foo:bar=baz zab'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(::RightScale::TaggerSpec::QUERY_RESULT))
      run_tagger(['-q', 'foo:bar=baz zab'])
      @error.should == []
      @output.should == [JSON.pretty_generate(::RightScale::TaggerSpec::QUERY_RESULT)]
    end

    it 'should query instances with a single tag containing ambiguous spaces and equals' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :query_tags, :tags => ['x:y=a b c:d=x y'] },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      query_result = { ::RightScale::TaggerSpec::RS_INSTANCE_ID_2 => ::RightScale::TaggerSpec::QUERY_RESULT[::RightScale::TaggerSpec::RS_INSTANCE_ID_2] }
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(query_result))
      run_tagger(['-q', 'x:y=a b c:d=x y'])
      @error.should == []
      @output.should == [JSON.pretty_generate(query_result)]
    end
  end

  context 'rs_tag --add' do
    it 'should add or update a tag on the instance' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :add_tag, :tag => 'x:y=z' },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(true))
      run_tagger(['-a', 'x:y=z'])
      @error.should == ["Successfully added tag x:y=z"]
      @output.should == []
    end
  end

  context 'rs_tag --remove' do
    it 'should remove a tag from the instance' do
      flexmock(subject).should_receive(:send_command).with(
        { :name => :remove_tag, :tag => 'x:y' },
        false,
        ::RightScale::Tagger::TAG_REQUEST_TIMEOUT,
        Proc).once.and_yield('stuff')
      flexmock(subject).should_receive(:serialize_operation_result).with('stuff').once.and_return(::RightScale::OperationResult.success(true))
      run_tagger(['-r', 'x:y'])
      @error.should == ["Successfully removed tag x:y"]
      @output.should == []
    end
  end

end
