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
require File.join(File.dirname(__FILE__), '..', 'lib', 'clouds', 'metadata_sources', 'http_metadata_source')
require 'json'

module RightScale
  module HttpMetadataSourceSpec

    MALFORMED_EC2_HTTP_RESPONSE_PREFIX = "2010-08-12 16:08:50: (server.c.1357) [note] sockets disabled, connection limit reached\n"

    METADATA_ROOT = ['latest', 'meta-data']
    METADATA_TREE = {
      "ami-id" => "ami-f4c495b1",
      "ami-launch-index" => "0",
      "ami-manifest-path" => "(unknown)",
      "block-device-mapping" => {
        "ami" => "/dev/sda1",
        "root" => "/dev/sda1",
        "swap" => "sda3"
      },
      "hostname" => "ip-10-162-159-118.us-west-1.compute.internal",
      "instance-action" => "none",
      "instance-id" => "i-fda502b9",
      "instance-type" => "m1.small",
      "local-hostname" => "ip-10-162-159-118.us-west-1.compute.internal",
      "local-ipv4" => "10.162.159.118",
      "placement" => {
        "availability-zone" => "us-west-1a"
      },
      "profile" => "windows",
      "public-hostname" => "ec2-204-236-145-162.us-west-1.compute.amazonaws.com",
      "public-ipv4" => "204.236.145.162",
      "public-keys" => {
        "0=windows_image_build_key" => {
          "openssh-key" => "ssh-rsa AAAAAAAAAA/BBBBBBBBBB/CCCCCCCCCCC/DDDDDDDDDEEEEEEE/EFFFFFFFFFFGGGGGGGG/GGHHHHHHHHIIIIIIIJJJ/JJJJJJJKKKKKKKKKLLLL/LLLLLLMMMMMMMMMMN/NNNNNNNOOOOOOOOOOOOOOOOOOOO/OOOOOPPPPPPPPPPPPPPPPQQQ/QQQQQQQQQQQQQQQQQQQQQQQQQQQQQ/RRRRRRRRRRRRRRRRRRRRRRRRRSSSSSSSS/SSSSSSSSSSSSSSTTTTTTTTTTTTTTUUUUUUUUUUUUUU/UUUUVVVVVVVVVVVVVVVVVVVVVVWWWWWWWWWWWWWWWWWWWWW/WWWXXXXXXXXXXXXXXXXXXXXXXXYYYYYYY windows_image_build_key\n"
        }
      },
      "reservation-id" => "r-0ddf0f49",
      "security-groups" => "windows_image_build"
    }

    USERDATA_ROOT = ['latest', 'user-data']
    USERDATA_LEAF = "RS_rn_url=amqp://1234567890@broker1-2.rightscale.com/right_net&RS_rn_id=1234567890&RS_server=my.rightscale.com&RS_rn_auth=1234567890&RS_api_url=https://my.rightscale.com/api/inst/ec2_instances/1234567890&RS_rn_host=:1,broker1-1.rightscale.com:0&RS_version=5.6.5&RS_sketchy=sketchy4-2.rightscale.com&RS_token=1234567890"
  end

  module MetadataSources

    class HttpMetadataSource
      # monkey patch for quicker testing of retries.
      RETRY_DELAY_FACTOR = 0.01
    end

  end

end

describe RightScale::MetadataSources::HttpMetadataSource do

  before(:each) do
    @runner = ::RightScale::FetchRunner.new
    @logger = @runner.setup_log
    @output_dir_path = File.join(::RightScale::RightLinkConfig[:platform].filesystem.temp_dir, 'rs_raw_metadata_writer_output')
    setup_metadata_provider
  end

  after(:each) do
    teardown_metadata_provider
    @logger = nil
    @runner.teardown_log
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    @output_dir_path = nil
  end

  def setup_metadata_provider
    # source is shared between cloud and user metadata providers.
    hosts = [:host => ::RightScale::FetchRunner::FETCH_TEST_SOCKET_ADDRESS, :port => ::RightScale::FetchRunner::FETCH_TEST_SOCKET_PORT]
    @metadata_source = RightScale::MetadataSources::HttpMetadataSource.new(:hosts => hosts, :logger => @logger)
    cloud_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => ::RightScale::HttpMetadataSourceSpec::METADATA_ROOT.join('/'))
    user_metadata_tree_climber = ::RightScale::MetadataTreeClimber.new(:root_path => ::RightScale::HttpMetadataSourceSpec::USERDATA_ROOT.join('/'),
                                                                       :has_children_override => lambda{ false } )

    # raw metadata writer.
    @cloud_raw_metadata_writer = ::RightScale::MetadataWriter.new(:file_name_prefix => ::RightScale::HttpMetadataSourceSpec::METADATA_ROOT.last,
                                                                  :output_dir_path => @output_dir_path)
    @user_raw_metadata_writer = ::RightScale::MetadataWriter.new(:file_name_prefix => ::RightScale::HttpMetadataSourceSpec::USERDATA_ROOT.last,
                                                                 :output_dir_path => @output_dir_path)

    # cloud metadata
    @cloud_metadata_provider = ::RightScale::MetadataProvider.new
    @cloud_metadata_provider.metadata_source = @metadata_source
    @cloud_metadata_provider.metadata_tree_climber = cloud_metadata_tree_climber
    @cloud_metadata_provider.raw_metadata_writer = @cloud_raw_metadata_writer

    # user metadata
    @user_metadata_provider = ::RightScale::MetadataProvider.new
    @user_metadata_provider.metadata_source = @metadata_source
    @user_metadata_provider.metadata_tree_climber = user_metadata_tree_climber
    @user_metadata_provider.raw_metadata_writer = @user_raw_metadata_writer
  end

  def teardown_metadata_provider
    @cloud_metadata_provider = nil
    @user_metadata_provider = nil
    @metadata_source.finish
    @metadata_source = nil
  end

  def verify_cloud_metadata(cloud_metadata)
    compare_tree = JSON::parse(::RightScale::HttpMetadataSourceSpec::METADATA_TREE.to_json)
    compare_tree["public-keys"] = compare_tree["public-keys"].dup
    compare_tree["public-keys"]["0"] = {"openssh-key" => compare_tree["public-keys"]["0=windows_image_build_key"]["openssh-key"].strip}
    compare_tree["public-keys"].delete_if { |key, value| key == "0=windows_image_build_key" }

    recursive_compare(compare_tree, cloud_metadata)
  end

  def recursive_compare(compare_tree, cloud_metadata)
    compare_tree.each_pair do |key, value|
      normalized_key = key.gsub(/=.*$/, '/').gsub('-', '_')
      if value.kind_of?(Hash)
        recursive_compare(value, cloud_metadata[normalized_key])
      else
        cloud_metadata[normalized_key].should == value
      end
    end
  end

  def verify_user_metadata(user_metadata)
    user_metadata.should == ::RightScale::HttpMetadataSourceSpec::USERDATA_LEAF
  end

  def verify_raw_metadata_writer(reader, metadata, subpath = [])
    if metadata.respond_to?(:has_key?)
      metadata.each do |key, value|
        # reversing dash to underscore substitution.  This appears to be valid for the
        # test data, but will fail if the test data keys ever contain '_' 
        verify_raw_metadata_writer(reader, value, subpath + [key.gsub('_','-')])
      end
    else
      result = reader.read(subpath)
      result.strip.should == metadata
    end
  end

  it 'should return empty metadata for HTTP calls which return 404s' do
    cloud_metadata, user_metadata = @runner.run_fetcher(@cloud_metadata_provider, @user_metadata_provider) do |server|
      # intentionally not mounting metadata
    end
    cloud_metadata.should == {}
    user_metadata.should == ""
  end

  it 'should succeed for successful HTTP calls' do
    cloud_metadata, user_metadata = @runner.run_fetcher(@cloud_metadata_provider, @user_metadata_provider) do |server|
      server.recursive_mount_metadata(::RightScale::HttpMetadataSourceSpec::METADATA_TREE, ::RightScale::HttpMetadataSourceSpec::METADATA_ROOT.clone)
      server.recursive_mount_metadata(::RightScale::HttpMetadataSourceSpec::USERDATA_LEAF, ::RightScale::HttpMetadataSourceSpec::USERDATA_ROOT.clone)
    end

    verify_cloud_metadata(cloud_metadata)
    verify_user_metadata(user_metadata)
    verify_raw_metadata_writer(@cloud_raw_metadata_writer, cloud_metadata)
    verify_raw_metadata_writer(@user_raw_metadata_writer, user_metadata, nil)
  end

  it 'should recover from successful HTTP calls which return malformed HTTP response' do
    requested_branch = false
    requested_leaf = false
    cloud_metadata = @runner.run_fetcher(@cloud_metadata_provider) do |server|
      server.recursive_mount_metadata(::RightScale::HttpMetadataSourceSpec::METADATA_TREE, ::RightScale::HttpMetadataSourceSpec::METADATA_ROOT.clone)

      # fail a branch request.
      branch_name = 'block-device-mapping'
      branch_metadata_path = ::RightScale::HttpMetadataSourceSpec::METADATA_ROOT.clone << branch_name
      branch_metadata = ::RightScale::HttpMetadataSourceSpec::METADATA_TREE[branch_name]
      branch_path = server.get_metadata_request_path(branch_metadata_path)
      branch_response = server.get_metadata_response(branch_metadata)
      server.unmount(branch_path)
      server.mount_proc(branch_path) do |request, response|
        response.body = branch_response
        unless requested_branch
          old_status_line = response.status_line
          response.instance_variable_set(:@injected_status_line, ::RightScale::HttpMetadataSourceSpec::MALFORMED_EC2_HTTP_RESPONSE_PREFIX + old_status_line)
          def response.status_line
            return @injected_status_line
          end
          requested_branch = true
        end
      end

      # fail a leaf request.
      leaf_name = 'root'
      leaf_metadata_path = branch_metadata_path.clone << leaf_name
      leaf_metadata = branch_metadata[leaf_name]
      leaf_path = server.get_metadata_request_path(leaf_metadata_path)
      leaf_response = server.get_metadata_response(leaf_metadata)
      server.unmount(leaf_path)
      server.mount_proc(leaf_path) do |request, response|
        response.body = leaf_response
        unless requested_leaf
          old_status_line = response.status_line
          response.instance_variable_set(:@injected_status_line, ::RightScale::HttpMetadataSourceSpec::MALFORMED_EC2_HTTP_RESPONSE_PREFIX + old_status_line)
          def response.status_line
            return @injected_status_line
          end
          requested_leaf = true
        end
      end
    end
    requested_branch.should == true
    requested_leaf.should == true

    verify_cloud_metadata(cloud_metadata)
    verify_raw_metadata_writer(@cloud_raw_metadata_writer, cloud_metadata)
  end

end
