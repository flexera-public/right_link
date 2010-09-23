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

    NO_MORE_CONNECTIONS_ERROR_RESPONSE = <<EOF
2010-08-12 16:08:50: (server.c.1357) [note] sockets disabled, connection limit reached
HTTP/1.0 404 Not Found
Content-Type: text/html
Content-Length: 345
Connection: close
Date: Thu, 12 Aug 2010 16:08:50 GMT
Server: EC2ws

<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
         "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
 <head>
  <title>404 - Not Found</title>
 </head>
 <body>
  <h1>404 - Not Found</h1>
 </body>
</html>
EOF

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
    metadata_provider = ::RightScale::Ec2MetadataProvider.new(:logger => @logger, :retry_delay_secs => 0.1, :max_curl_retries => 3)
    metadata_formatter = ::RightScale::Ec2MetadataFormatter.new
    mock_cloud_info
    lambda do
      @runner.run_fetcher(metadata_provider, metadata_formatter) do |data, connector|
        @logger.debug("data = #{data}")
        connector.close_connection  # rudely close without responding; cURL will consider this an error.
      end
    end.should raise_error
  end

  it 'should recover from successful cURL calls which return error information' do
    metadata_provider = ::RightScale::Ec2MetadataProvider.new(:logger => @logger, :retry_delay_secs => 0.1)
    metadata_formatter = ::RightScale::Ec2MetadataFormatter.new
    requested_branch = false
    requested_leaf = false
    mock_cloud_info
    metadata = @runner.run_fetcher(metadata_provider, metadata_formatter) do |data, connector|
      @logger.debug("data = #{data}")

      # ensure we send error response for both a branch and a leaf.
      request_path = @runner.get_metadata_request_path(data)
      is_branch = /\/$/.match(request_path)
      send_error = false
      if is_branch && !requested_branch
        send_error = true
        requested_branch = true
      elsif !is_branch && !requested_leaf
        send_error = true
        requested_leaf = true
      end

      # respond with error or with valid response.
      if send_error
        response = ::RightScale::Ec2MetadataProviderSpec::NO_MORE_CONNECTIONS_ERROR_RESPONSE
      else
        response = @runner.get_metadata_response(data, ::RightScale::Ec2MetadataProviderSpec::METADATA_TREE)
      end
      @logger.debug("response = \"#{response}\"")
      connector.send_data(response)
      connector.close_connection_after_writing
    end
    requested_branch.should == true
    requested_leaf.should == true
    metadata.size.should == 18
    metadata["EC2_INSTANCE_TYPE"].should == "m1.small"
  end

  it 'should succeed for successful cURL calls' do
    metadata_provider = ::RightScale::Ec2MetadataProvider.new(:logger => @logger, :retry_delay_secs => 0.1)
    metadata_formatter = ::RightScale::Ec2MetadataFormatter.new
    mock_cloud_info
    metadata = @runner.run_fetcher(metadata_provider, metadata_formatter) do |data, connector|
      @logger.debug("data = #{data}")
      response = @runner.get_metadata_response(data, ::RightScale::Ec2MetadataProviderSpec::METADATA_TREE)
      @logger.debug("response = \"#{response}\"")
      connector.send_data(response)
      connector.close_connection_after_writing
    end
    metadata.size.should == 18
    metadata["EC2_RESERVATION_ID"].should == "r-0ddf0f49"
  end

end
