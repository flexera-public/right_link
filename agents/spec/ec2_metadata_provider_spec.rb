#
# Copyright (c) 2010 RightScale Inc
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
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'ec2_metadata_provider'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'ec2_metadata_formatter'))
require File.join(File.dirname(__FILE__), 'fetch_runner')

module RightScale
  module Ec2MetadataProviderSpec

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

  end

  class Ec2MetadataProvider
    # monkey patch for quicker testing of retries.
    RETRY_DELAY_FACTOR = 0.01
  end

end

describe RightScale::Ec2MetadataProvider do

  def mock_cloud_info
    mock_url = "#{::RightScale::FetchRunner::FETCH_TEST_SOCKET_ADDRESS}:#{::RightScale::FetchRunner::FETCH_TEST_SOCKET_PORT}"
    flexmock(RightScale::CloudInfo).should_receive(:metadata_server_url).and_return(mock_url)
  end

  before(:each) do
    @runner = ::RightScale::FetchRunner.new
    @logger = @runner.setup_log
  end

  after(:each) do
    @logger = nil
    @runner.teardown_log
  end

  it 'should raise exception for failing cURL calls' do
    metadata_provider = ::RightScale::Ec2MetadataProvider.new(:logger => @logger)
    metadata_formatter = ::RightScale::Ec2MetadataFormatter.new
    mock_cloud_info
    lambda do
      @runner.run_fetcher(metadata_provider, metadata_formatter) do |server|
        # intentionally not mounting any paths
      end
    end.should raise_error(::RightScale::Ec2MetadataProvider::HttpMetadataException)
  end

  it 'should recover from successful cURL calls which return malformed HTTP response' do
    metadata_provider = ::RightScale::Ec2MetadataProvider.new(:logger => @logger)
    metadata_formatter = ::RightScale::Ec2MetadataFormatter.new
    requested_branch = false
    requested_leaf = false
    mock_cloud_info
    metadata = @runner.run_fetcher(metadata_provider, metadata_formatter) do |server|
      server.recursive_mount_metadata(::RightScale::Ec2MetadataProviderSpec::METADATA_TREE, ::RightScale::Ec2MetadataProviderSpec::METADATA_ROOT.clone)

      # fail a branch request.
      branch_name = 'block-device-mapping'
      branch_metadata_path = ::RightScale::Ec2MetadataProviderSpec::METADATA_ROOT.clone << branch_name
      branch_metadata = ::RightScale::Ec2MetadataProviderSpec::METADATA_TREE[branch_name]
      branch_path = server.get_metadata_request_path(branch_metadata_path)
      branch_response = server.get_metadata_response(branch_metadata)
      server.unmount(branch_path)
      server.mount_proc(branch_path) do |request, response|
        response.body = branch_response
        unless requested_branch
          old_status_line = response.status_line
          response.instance_variable_set(:@injected_status_line, ::RightScale::Ec2MetadataProviderSpec::MALFORMED_EC2_HTTP_RESPONSE_PREFIX + old_status_line)
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
          response.instance_variable_set(:@injected_status_line, ::RightScale::Ec2MetadataProviderSpec::MALFORMED_EC2_HTTP_RESPONSE_PREFIX + old_status_line)
          def response.status_line
            return @injected_status_line
          end
          requested_leaf = true
        end
      end
    end
    requested_branch.should == true
    requested_leaf.should == true
    metadata.size.should == 19

    # verify normal responses.
    metadata["EC2_INSTANCE_TYPE"].should == "m1.small"
    metadata["EC2_RESERVATION_ID"].should == "r-0ddf0f49"

    # verify malformed responses were retried.
    metadata["EC2_BLOCK_DEVICE_MAPPING_AMI"].should == "/dev/sda1"
    metadata["EC2_BLOCK_DEVICE_MAPPING_ROOT"].should == "/dev/sda1"
  end

  it 'should succeed for successful cURL calls' do
    metadata_provider = ::RightScale::Ec2MetadataProvider.new(:logger => @logger)
    metadata_formatter = ::RightScale::Ec2MetadataFormatter.new
    mock_cloud_info
    metadata = @runner.run_fetcher(metadata_provider, metadata_formatter) do |server|
      server.recursive_mount_metadata(::RightScale::Ec2MetadataProviderSpec::METADATA_TREE, ::RightScale::Ec2MetadataProviderSpec::METADATA_ROOT.clone)
    end
    metadata.size.should == 19

    # verify normal responses.
    metadata["EC2_INSTANCE_TYPE"].should == "m1.small"
    metadata["EC2_RESERVATION_ID"].should == "r-0ddf0f49"
    metadata["EC2_BLOCK_DEVICE_MAPPING_AMI"].should == "/dev/sda1"
    metadata["EC2_BLOCK_DEVICE_MAPPING_ROOT"].should == "/dev/sda1"
  end

end
