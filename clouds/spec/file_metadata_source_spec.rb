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
require File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'metadata_sources', 'file_metadata_source')

module RightScale
  module FileMetadataSourceSpec

    CLOUD_METADATA_FILE_TEXT = <<EOF
public-hostname=myCloud-1-2-3-4.com
public-ip=1.2.3.4
private-ip=10.11.12.13
EOF

    USER_METADATA_FILE_TEXT = <<EOF
RS_rn_url=amqp://1234567890@broker1-2.rightscale.com/right_net
RS_rn_id=1234567890
RS_server=my.rightscale.com
RS_rn_auth=1234567890
RS_api_url=https://my.rightscale.com/api/inst/ec2_instances/1234567890
RS_rn_host=:1,broker1-1.rightscale.com:0
RS_version=5.8.0
RS_sketchy=sketchy4-2.rightscale.com
RS_token=1234567890
EOF
  end

end

describe RightScale::MetadataSources::FileMetadataSource do

  before(:each) do
    setup_metadata_provider
  end

  after(:each) do
    teardown_metadata_provider
  end

  # Parses rackspace user metadata into a hash.
  #
  # === Parameters
  # tree_climber(MetadataTreeClimber):: tree climber
  # data(String):: raw data
  #
  # === Return
  # result(Hash):: Hash-like leaf value
  def create_user_metadata_leaf(tree_climber, data)
    result = tree_climber.create_branch
    ::RightScale::CloudUtilities.split_metadata(data, "\n", result)
    result
  end

  def setup_metadata_provider
    temp_dir = ::RightScale::RightLinkConfig[:platform].filesystem.temp_dir
    @source_dir_path = File.join(temp_dir, 'rs_file_metadata_sources')
    FileUtils.mkdir_p(@source_dir_path)
    @cloud_metadata_source_file_path = File.join(@source_dir_path, 'cloud_metadata.dict')
    @user_metadata_source_file_path = File.join(@source_dir_path, 'user_metadata.dict')
    @metadata_source = ::RightScale::MetadataSources::FileMetadataSource.new(:cloud_metadata_source_file_path => @cloud_metadata_source_file_path,
                                                                           :user_metadata_source_file_path => @user_metadata_source_file_path)
    cloud_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => ::RightScale::MetadataSources::FileMetadataSource::DEFAULT_CLOUD_METADATA_ROOT_PATH,
                                                                        :has_children_override => lambda{ false },
                                                                        :create_leaf_override => method(:create_user_metadata_leaf))
    user_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => ::RightScale::MetadataSources::FileMetadataSource::DEFAULT_USER_METADATA_ROOT_PATH,
                                                                       :has_children_override => lambda{ false },
                                                                       :create_leaf_override => method(:create_user_metadata_leaf))
    # cloud metadata
    @cloud_metadata_provider = ::RightScale::MetadataProvider.new
    @cloud_metadata_provider.metadata_source = @metadata_source
    @cloud_metadata_provider.metadata_tree_climber = cloud_metadata_tree_climber

    # user metadata
    @user_metadata_provider = ::RightScale::MetadataProvider.new
    @user_metadata_provider.metadata_source = @metadata_source
    @user_metadata_provider.metadata_tree_climber = user_metadata_tree_climber
  end

  def teardown_metadata_provider
    FileUtils.rm_rf(@source_dir_path) if File.directory?(@source_dir_path)
    @source_dir_path = nil
    @cloud_metadata_source_file_path = nil
    @user_metadata_source_file_path = nil
    @metadata_source.finish
    @metadata_source = nil
    @cloud_metadata_provider = nil
    @user_metadata_provider = nil
  end

  def verify_cloud_metadata(cloud_metadata)
    data = ::RightScale::FileMetadataSourceSpec::CLOUD_METADATA_FILE_TEXT
    compare_hash = ::RightScale::CloudUtilities.split_metadata(data, "\n", {})

    cloud_metadata.should == compare_hash
  end

  def verify_user_metadata(user_metadata)
    data = ::RightScale::FileMetadataSourceSpec::USER_METADATA_FILE_TEXT
    compare_hash = ::RightScale::CloudUtilities.split_metadata(data, "\n", {})

    user_metadata.should == compare_hash
  end

  it 'should return metadata when expected files appear on disk' do
    File.open(@cloud_metadata_source_file_path, "w") { |f| f.write(::RightScale::FileMetadataSourceSpec::CLOUD_METADATA_FILE_TEXT) }
    File.open(@user_metadata_source_file_path, "w") { |f| f.write(::RightScale::FileMetadataSourceSpec::USER_METADATA_FILE_TEXT) }

    cloud_metadata = @cloud_metadata_provider.build_metadata
    verify_cloud_metadata(cloud_metadata)

    user_metadata = @user_metadata_provider.build_metadata
    verify_user_metadata(user_metadata)
  end

  it 'should raise QueryError when files are missing' do
    lambda{ cloud_metadata = @cloud_metadata_provider.build_metadata }.should raise_error(::RightScale::MetadataSource::QueryFailed)
    lambda{ cloud_metadata = @user_metadata_provider.build_metadata }.should raise_error(::RightScale::MetadataSource::QueryFailed)
  end

  it 'should return empty metadata when files are empty or all whitespace' do
    File.open(@cloud_metadata_source_file_path, "w") { |f| f.write("") }
    File.open(@user_metadata_source_file_path, "w") { |f| f.write(" \t\r\n") }

    cloud_metadata = @cloud_metadata_provider.build_metadata
    cloud_metadata.should == {}

    user_metadata = @user_metadata_provider.build_metadata
    user_metadata.should == {}
  end

  it 'should return empty metadata when file paths are unspecified' do
    @metadata_source.cloud_metadata_source_file_path = nil
    @metadata_source.user_metadata_source_file_path = nil

    cloud_metadata = @cloud_metadata_provider.build_metadata
    cloud_metadata.should == {}

    user_metadata = @user_metadata_provider.build_metadata
    user_metadata.should == {}
  end

end
