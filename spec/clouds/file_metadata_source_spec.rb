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

require File.expand_path('../spec_helper', __FILE__)
require File.expand_path('../../../lib/clouds/metadata_sources/file_metadata_source', __FILE__)

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


  def setup_metadata_provider
    temp_dir = ::RightScale::Platform.filesystem.temp_dir
    @source_dir_path = File.join(temp_dir, 'rs_file_metadata_sources')
    FileUtils.mkdir_p(@source_dir_path)
    @cloud_metadata_source_file_path = File.join(@source_dir_path, 'cloud_metadata.dict')
    @user_metadata_source_file_path = File.join(@source_dir_path, 'user_metadata.dict')
    @logger = flexmock('logger')

    # metadat source
    @metadata_source = ::RightScale::MetadataSources::FileMetadataSource.new(:logger => @logger)
  end

  def teardown_metadata_provider
    FileUtils.rm_rf(@source_dir_path) if File.directory?(@source_dir_path)
    @metadata_source.finish
  end

  def verify_cloud_metadata(cloud_metadata)
    data = ::RightScale::FileMetadataSourceSpec::CLOUD_METADATA_FILE_TEXT
    cloud_metadata.should == data
  end

  def verify_user_metadata(user_metadata)
    data = ::RightScale::FileMetadataSourceSpec::USER_METADATA_FILE_TEXT
    user_metadata.should == data
  end

  it 'should return metadata when expected files appear on disk' do
    File.open(@cloud_metadata_source_file_path, "w") { |f| f.write(::RightScale::FileMetadataSourceSpec::CLOUD_METADATA_FILE_TEXT) }
    File.open(@user_metadata_source_file_path, "w") { |f| f.write(::RightScale::FileMetadataSourceSpec::USER_METADATA_FILE_TEXT) }

    cloud_metadata = @metadata_source.get(@cloud_metadata_source_file_path)
    verify_cloud_metadata(cloud_metadata)

    user_metadata = @metadata_source.get(@user_metadata_source_file_path)
    verify_user_metadata(user_metadata)
  end

  it 'should raise QueryError when files are missing' do
    lambda{ cloud_metadata = @metadata_source.get(@cloud_metadata_source_file_path) }.should raise_error(::RightScale::MetadataSource::QueryFailed)
    lambda{ cloud_metadata = @metadata_source.get(@user_metadata_source_file_path) }.should raise_error(::RightScale::MetadataSource::QueryFailed)
  end


end
