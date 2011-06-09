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

module RightScale

  class CloudFactorySpec

    CLOUD_NAME = 'connor'
    CLOUD_METADATA_ROOT = 'cloud metadata'
    CLOUD_METADATA = {'ABC' => ['easy', 123], 'simple' => "do re mi", 'abc_123' => {'baby' => [:you, :me, :girl] }}
    USER_METADATA_ROOT = 'user metadata'
    USER_METADATA = { 'RS_RN_ID' => '12345', 'RS_SERVER' => 'my.rightscale.com' }
    METADATA = { CLOUD_METADATA_ROOT => CLOUD_METADATA, USER_METADATA_ROOT => USER_METADATA }

    # Uses DSL to describe a mock cloud for testing purposes.
    class MockCloud
      include Cloud

      metadata_source 'metadata_sources/mock_metadata_source'
      metadata_writers 'metadata_writers/dictionary_metadata_writer'

      # describe a custom dependency base path for mock_metadata_source
      dependency_base_paths(File.join(File.dirname(__FILE__)))

      extension_script_base_paths(File.join(File.dirname(__FILE__), 'scripts', CLOUD_NAME))

      def initialize(options)
        # super.
        super(options)

        # all options are specific to the category of dependency and can even be
        # specific to the exact dependency type.
        default_options([:metadata_source, :mock_metadata_source, :mock_metadata], METADATA)
        default_options([:metadata_tree_climber, :create_leaf_override], lambda{ |_, data| data })

        # options can be further distinguished between cloud and user metadata
        # or can be used by both if kind is not specified (as in the
        # mock_metadata_source example).
        default_options([:cloud_metadata, :metadata_tree_climber, :root_path], CLOUD_METADATA_ROOT)
        default_options([:user_metadata, :metadata_tree_climber, :root_path], USER_METADATA_ROOT)
      end

    end

    # each cloud should self-register when declared.
    ::RightScale::CloudFactory.instance.register(CLOUD_NAME, MockCloud)

  end

end

describe RightScale::CloudFactory do

  before(:each) do
    @output_dir_path = File.join(::RightScale::RightLinkConfig[:platform].filesystem.temp_dir, 'rs_cloud_factory_output')
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
  end

  after(:each) do
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    @output_dir_path = nil
  end

  it 'should raise exception for unknown cloud' do
    lambda{ ::RightScale::CloudFactory.instance.create('bogus') }.should raise_exception ::RightScale::CloudFactory::UnknownCloud
  end

  it 'should register new clouds with multiple aliases' do
    aliases = ['Highlander', 'MacLeod']
    ::RightScale::CloudFactory.instance.register(aliases, ::RightScale::CloudFactorySpec::MockCloud)
    last_cloud = nil
    (aliases + [::RightScale::CloudFactorySpec::CLOUD_NAME]).each do |cloud_alias|
      cloud = ::RightScale::CloudFactory.instance.create(cloud_alias)
      cloud.class.should == ::RightScale::CloudFactorySpec::MockCloud
      cloud.name.should == cloud_alias
      last_cloud.should_not == cloud  # factory always returns new instance
      last_cloud = cloud
    end
  end

  it 'should create the default cloud when cloud file exists' do
    mock_state_dir_path = File.join(@output_dir_path, 'rightscale.d')
    mock_cloud_file_path = File.join(mock_state_dir_path, 'cloud')
    filesystem = ::RightScale::RightLinkConfig[:platform].filesystem
    flexmock(filesystem).should_receive(:right_scale_state_dir).and_return(mock_state_dir_path)
    lambda{ ::RightScale::CloudFactory.instance.create }.should raise_exception ::RightScale::CloudFactory::UnknownCloud
    FileUtils.mkdir_p(mock_state_dir_path)
    File.open(mock_cloud_file_path, "w") { |f| f.puts(::RightScale::CloudFactorySpec::CLOUD_NAME) }
    cloud = ::RightScale::CloudFactory.instance.create
    cloud.class.should == ::RightScale::CloudFactorySpec::MockCloud
    cloud.name.should == ::RightScale::CloudFactorySpec::CLOUD_NAME
  end

  it 'should create clouds that can format and write metadata' do
    options = { :metadata_writers => { :output_dir_path => @output_dir_path } }
    cloud = ::RightScale::CloudFactory.instance.create(::RightScale::CloudFactorySpec::CLOUD_NAME, options)
    cloud.write_metadata
    File.directory?(@output_dir_path).should be_true
    writer_type = cloud.class.metadata_writers.first

    # note that the default metadata formatter automatically uses the shortest
    # alias as the prefix for key names (i.e. 'CONNER_') and the dictionary
    # writer automatically converts right-hand values to text and writes the
    # first line or array element only (currently all known metadata values are
    # single lines of text).
    result = cloud.read_metadata(:cloud_metadata, writer_type)
    result.should == {"CONNOR_SIMPLE"=>"do re mi", "CONNOR_ABC_123_BABY"=>"you", "CONNOR_ABC"=>"easy"}
    result = cloud.read_metadata(:user_metadata, writer_type)
    result.should == {"RS_RN_ID"=>"12345", "RS_SERVER"=>"my.rightscale.com"}
  end

  it 'should create clouds that can be extended by external scripts' do
    cloud = ::RightScale::CloudFactory.instance.create(::RightScale::CloudFactorySpec::CLOUD_NAME)
    result = cloud.wait_for_instance_ready
    result[:exitstatus].should == 0
    result[:output].should == "Simulating wait for something to happen\nSomething happened!\n"
  end

end
