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
require File.join(File.dirname(__FILE__), 'fetch_runner')
require File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'metadata_sources', 'selective_metadata_source')
require File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'metadata_sources', 'file_metadata_source')
require File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'metadata_sources', 'http_metadata_source')
require 'json'

module RightScale
  module SelectiveMetadataSourceSpec

    TEMP_DIR_PATH = File.join(RightLinkConfig.platform.filesystem.temp_dir, 'selective-metadata-spec-B967A8D4157329C2B4191D73C199BCEF')
    SHEBANG_REGEX = /^#!/

    CLOUD_METADATA_ROOT = ['latest', 'meta-data']
    HTTP_CLOUD_METADATA = { "AAA" => "aaa", "BBB" => "bbb" }

    USER_METADATA_ROOT = ['latest', 'user-data']
    HTTP_USER_METADATA = "XXX=xxx&YYY=yyy"

    CLOUD_METADATA_FILE_PATH = File.join(TEMP_DIR_PATH, 'cloud-data.txt')

    USER_METADATA_FILE_PATH = File.join(TEMP_DIR_PATH, 'user-data.txt')
    FILE_USER_METADATA = <<EOF
RS_rrr=rrr
RS_sss=sss
EOF

  end

end

describe RightScale::MetadataSources::SelectiveMetadataSource do

  before(:each) do
    @runner = ::RightScale::FetchRunner.new
    @logger = @runner.setup_log
    @output_dir_path = File.join(::RightScale::SelectiveMetadataSourceSpec::TEMP_DIR_PATH, 'rs_raw_metadata_writer_output')
    setup_metadata_provider
  end

  after(:each) do
    teardown_metadata_provider
    @logger = nil
    @runner.teardown_log
    FileUtils.rm_rf(::RightScale::SelectiveMetadataSourceSpec::TEMP_DIR_PATH) if File.directory?(::RightScale::SelectiveMetadataSourceSpec::TEMP_DIR_PATH)
    @output_dir_path = nil
  end

  def setup_metadata_provider
    # source is shared between cloud and user metadata providers.
    hosts = [:host => ::RightScale::FetchRunner::FETCH_TEST_SOCKET_ADDRESS, :port => ::RightScale::FetchRunner::FETCH_TEST_SOCKET_PORT]
    @cloud_metadata_root_path = ::RightScale::SelectiveMetadataSourceSpec::CLOUD_METADATA_ROOT.join('/')
    cloud_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => @cloud_metadata_root_path)
    @user_metadata_root_path = ::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_ROOT.join('/')
    user_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => @user_metadata_root_path,
                                                                       :has_children_override => lambda{ false } )
    @mock_cloud = flexmock("cloud")
    flexmock(@mock_cloud).
      should_receive(:create_dependency_type).
      with(:cloud_metadata, :metadata_source, "metadata_sources/http_metadata_source").
      and_return(::RightScale::MetadataSources::HttpMetadataSource.new(:hosts => hosts, :logger => @logger))
    flexmock(@mock_cloud).
      should_receive(:create_dependency_type).
      with(:cloud_metadata, :metadata_source, "metadata_sources/file_metadata_source").
      and_return(::RightScale::MetadataSources::FileMetadataSource.new(:cloud_metadata_root_path => cloud_metadata_tree_climber.root_path,
                                                                      :cloud_metadata_source_file_path => ::RightScale::SelectiveMetadataSourceSpec::CLOUD_METADATA_FILE_PATH,
                                                                      :user_metadata_root_path => user_metadata_tree_climber.root_path,
                                                                       :user_metadata_source_file_path => ::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_FILE_PATH))

    # cloud metadata
    @cloud_metadata_provider = ::RightScale::MetadataProvider.new
    @cloud_metadata_provider.metadata_tree_climber = cloud_metadata_tree_climber

    # user metadata
    @user_metadata_provider = ::RightScale::MetadataProvider.new
    @user_metadata_provider.metadata_tree_climber = user_metadata_tree_climber
  end

  def teardown_metadata_provider
    @cloud_metadata_provider = nil
    @cloud_metadata_root_path = nil
    @user_metadata_provider = nil
    @user_metadata_root_path = nil
    if @selective_metadata_source
      @selective_metadata_source.finish
      @selective_metadata_source = nil
    end
  end

  # Selects metadata from multiple sources in support of serverizing existing
  # long-running instances. Stops merging metadata as soon as RS_ variables
  # are found.
  def select_rs_metadata(_, path, metadata_source_type, query_result, previous_metadata)
    # note that clouds can extend this cloud and change the user root option.
    query_next_metadata = false
    merged_metadata = query_result
    if path == @user_metadata_root_path
      # metadata from file source is delimited by newline while metadata from http
      # is delimited by ampersand (unless shebang is present for legacy reasons).
      # convert ampersand-delimited to newline-delimited for easier comparison
      # with regular expression.
      previous_metadata.strip!
      query_result.strip!
      if (metadata_source_type == 'metadata_sources/file_metadata_source') || (query_result =~ ::RightScale::SelectiveMetadataSourceSpec::SHEBANG_REGEX)
        current_metadata = query_result.gsub("\r\n", "\n").strip
      else
        current_metadata = query_result.gsub("&", "\n").strip
      end

      # will query next source only if current metadata does not contain RS_
      query_next_metadata = !(current_metadata =~ /^RS_/)
      merged_metadata = (previous_metadata + "\n" + current_metadata).strip
      merged_metadata = merged_metadata.gsub("\n", "&") unless merged_metadata =~ ::RightScale::SelectiveMetadataSourceSpec::SHEBANG_REGEX
    end
    return {:query_next_metadata => query_next_metadata, :merged_metadata => merged_metadata}
  end

  it 'should not select metadata from multiple sources when first source gives metadata' do
    # http then file source
    @selective_metadata_source = ::RightScale::MetadataSources::SelectiveMetadataSource.new(
      :metadata_source_types => ['metadata_sources/http_metadata_source', 'metadata_sources/file_metadata_source'],
      :cloud => @mock_cloud)
    @cloud_metadata_provider.metadata_source = @selective_metadata_source
    @user_metadata_provider.metadata_source = @selective_metadata_source

    cloud_metadata, user_metadata = @runner.run_fetcher(@cloud_metadata_provider, @user_metadata_provider) do |server|
      server.recursive_mount_metadata(::RightScale::SelectiveMetadataSourceSpec::HTTP_CLOUD_METADATA, ::RightScale::SelectiveMetadataSourceSpec::CLOUD_METADATA_ROOT.clone)
      server.recursive_mount_metadata(::RightScale::SelectiveMetadataSourceSpec::HTTP_USER_METADATA, ::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_ROOT.clone)
    end

    cloud_metadata.should == ::RightScale::SelectiveMetadataSourceSpec::HTTP_CLOUD_METADATA
    user_metadata.should == ::RightScale::SelectiveMetadataSourceSpec::HTTP_USER_METADATA
  end

  it 'should select metadata from secondary sources when first source does not give metadata' do
    # file then http source
    @selective_metadata_source = ::RightScale::MetadataSources::SelectiveMetadataSource.new(
      :metadata_source_types => ['metadata_sources/file_metadata_source', 'metadata_sources/http_metadata_source'],
      :cloud => @mock_cloud)
    @cloud_metadata_provider.metadata_source = @selective_metadata_source
    @user_metadata_provider.metadata_source = @selective_metadata_source

    # write file metadata.
    FileUtils.mkdir_p(::RightScale::SelectiveMetadataSourceSpec::TEMP_DIR_PATH)
    File.open(::RightScale::SelectiveMetadataSourceSpec::CLOUD_METADATA_FILE_PATH, "w") do |f|
      # empty file
    end
    File.open(::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_FILE_PATH, "w") do |f|
      # empty file
    end

    cloud_metadata, user_metadata = @runner.run_fetcher(@cloud_metadata_provider, @user_metadata_provider) do |server|
      server.recursive_mount_metadata({}, ::RightScale::SelectiveMetadataSourceSpec::CLOUD_METADATA_ROOT.clone)
      server.recursive_mount_metadata(::RightScale::SelectiveMetadataSourceSpec::HTTP_USER_METADATA, ::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_ROOT.clone)
    end

    cloud_metadata.should == {}
    user_metadata.should == ::RightScale::SelectiveMetadataSourceSpec::HTTP_USER_METADATA
  end

  it 'should allow override of selection of metadata' do
    # http, file, mock source
    @selective_metadata_source = ::RightScale::MetadataSources::SelectiveMetadataSource.new(
      :metadata_source_types => ['metadata_sources/http_metadata_source',
                                 'metadata_sources/file_metadata_source',
                                 'bogus'],  # should never be created
      :cloud => @mock_cloud,
      :select_metadata_override => method(:select_rs_metadata))
    @cloud_metadata_provider.metadata_source = @selective_metadata_source
    @user_metadata_provider.metadata_source = @selective_metadata_source

    # write file metadata.
    FileUtils.mkdir_p(::RightScale::SelectiveMetadataSourceSpec::TEMP_DIR_PATH)
    File.open(::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_FILE_PATH, "w") do |f|
      f.puts(::RightScale::SelectiveMetadataSourceSpec::FILE_USER_METADATA)
    end

    cloud_metadata, user_metadata = @runner.run_fetcher(@cloud_metadata_provider, @user_metadata_provider) do |server|
      server.recursive_mount_metadata(::RightScale::SelectiveMetadataSourceSpec::HTTP_CLOUD_METADATA, ::RightScale::SelectiveMetadataSourceSpec::CLOUD_METADATA_ROOT.clone)
      server.recursive_mount_metadata(::RightScale::SelectiveMetadataSourceSpec::HTTP_USER_METADATA, ::RightScale::SelectiveMetadataSourceSpec::USER_METADATA_ROOT.clone)
    end

    # selects first cloud source (for simplicity).
    # merges first and second file source.
    # bogus source is never instantiated because selective criteria is satisfied.
    cloud_metadata.should == ::RightScale::SelectiveMetadataSourceSpec::HTTP_CLOUD_METADATA
    file_user_metadata = ::RightScale::SelectiveMetadataSourceSpec::FILE_USER_METADATA.strip.gsub("\n", "&")
    user_metadata.should == ::RightScale::SelectiveMetadataSourceSpec::HTTP_USER_METADATA + "&" + file_user_metadata
  end

end
