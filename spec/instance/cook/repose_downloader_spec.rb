#
# Copyright (c) 2009-2013 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook'))

def mock_response(message, code)
  res = Net::HTTPInternalServerError.new('1.1', message, code)
  net_http_res = flexmock("Net HTTP Response")
  net_http_res.should_receive(:code).and_return(code)
  response = RestClient::Response.create("#{code}: #{message}", net_http_res, [])
  flexmock(RestClient::Request).should_receive(:execute).and_yield(response, nil, res)
end

module RightScale
  describe ReposeDownloader do

    before(:each) do
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "repose-hostname", "1.2.3.4", 2, 1, 6], ["AF_INET", 443, "repose-hostname", "5.6.7.8", 2, 1, 6]])
    end

    let(:hostname)    { 'repose-hostname' }
    let(:attachment)  { "https://#{hostname}:443/attachments/1/98c272b109c592ae4d4670d3279c8df282d6e681?md5=98c272b109c592ae4d4670d3279c8df282d6e681&expiration=1336631701&signature=XPQwxEJnt8%2BWXReZwVLSdJOtK0XNfuEd6K7vA8L%2FivT7L8ATDQyjmnv3%2Flrx%0ARfUrMInl007MhEY35IwPe%2BWfNI2Q8Je7LiN6ShYjVtA%2BfEpbN5tVkUPDNTO3%0A%2Ba%2F9EZJKy4%2Bl1ABBLn0uts65Cwr7zH%2BLZvsFQUctq25T0uY0XpY%3D%0A&signer=my" }
    let(:cookbook)    { "/cookbooks/98c272b109c592ae4d4670d3279c8df282d6e681?md5=98c272b109c592ae4d4670d3279c8df282d6e681&expiration=1336631701&signature=XPQwxEJnt8%2BWXReZwVLSdJOtK0XNfuEd6K7vA8L%2FivT7L8ATDQyjmnv3%2Flrx%0ARfUrMInl007MhEY35IwPe%2BWfNI2Q8Je7LiN6ShYjVtA%2BfEpbN5tVkUPDNTO3%0A%2Ba%2F9EZJKy4%2Bl1ABBLn0uts65Cwr7zH%2BLZvsFQUctq25T0uY0XpY%3D%0A&signer=my" }
    subject { ReposeDownloader.new([hostname]) }

    shared_examples_for 'ConnectionException' do
      it 'should fail to download after retrying if a ConnectionException is raised' do
        if exception
          flexmock(RestClient::Request).should_receive(:execute).and_raise(exception)
        else
          mock_response(message, code)
        end

        flexmock(ReposeDownloader.logger).should_receive(:info).times(ReposeDownloader::RETRY_MAX_ATTEMPTS)
        flexmock(ReposeDownloader.logger).should_receive(:error).times(ReposeDownloader::RETRY_MAX_ATTEMPTS + 2)

        lambda { subject.download(attachment) { |response| response } }.should raise_error(RightScale::ReposeDownloader::ConnectionException)
      end
    end

    shared_examples_for 'DownloadException' do
      it 'should fail to download without retrying if a DownloadException is raised' do
        mock_response(message, code)

        flexmock(ReposeDownloader.logger).should_receive(:info).once
        flexmock(ReposeDownloader.logger).should_receive(:error).twice

        lambda { subject.download(attachment) { |response| response } }.should raise_error(RightScale::ReposeDownloader::DownloadException)
      end
    end

    context :resolve do
      it 'should resolve hostnames into IP addresses' do
        subject.send(:resolve, [hostname]).should == { "1.2.3.4" => hostname, "5.6.7.8" => hostname }
      end
    end

    context :parse_resource do
      it 'should parse attachments correctly' do
        subject.send(:parse_resource, attachment).should == "/attachments/1/98c272b109c592ae4d4670d3279c8df282d6e681?md5=98c272b109c592ae4d4670d3279c8df282d6e681&expiration=1336631701&signature=XPQwxEJnt8%2BWXReZwVLSdJOtK0XNfuEd6K7vA8L%2FivT7L8ATDQyjmnv3%2Flrx%0ARfUrMInl007MhEY35IwPe%2BWfNI2Q8Je7LiN6ShYjVtA%2BfEpbN5tVkUPDNTO3%0A%2Ba%2F9EZJKy4%2Bl1ABBLn0uts65Cwr7zH%2BLZvsFQUctq25T0uY0XpY%3D%0A&signer=my"
      end

      it 'should parse cookbooks correctly' do
        subject.send(:parse_resource, cookbook).should == "/cookbooks/98c272b109c592ae4d4670d3279c8df282d6e681?md5=98c272b109c592ae4d4670d3279c8df282d6e681&expiration=1336631701&signature=XPQwxEJnt8%2BWXReZwVLSdJOtK0XNfuEd6K7vA8L%2FivT7L8ATDQyjmnv3%2Flrx%0ARfUrMInl007MhEY35IwPe%2BWfNI2Q8Je7LiN6ShYjVtA%2BfEpbN5tVkUPDNTO3%0A%2Ba%2F9EZJKy4%2Bl1ABBLn0uts65Cwr7zH%2BLZvsFQUctq25T0uY0XpY%3D%0A&signer=my"
      end
    end

    context :details do
      let(:resource)  { 'resource' }
      let(:size)      { '10' }
      let(:speed)     { '5' }

      it 'should return the details of the most recent download' do
        subject.instance_variable_set(:@sanitized_resource, resource)
        subject.instance_variable_set(:@size, size)
        subject.instance_variable_set(:@speed, speed)

        subject.details.should == "Downloaded '#{resource}' (#{size} B) at #{speed} B/s"
      end
    end

    context :download do
      it 'should download an attachment' do
        res = Net::HTTPSuccess.new('1.1', 'bar', 200)
        flexmock(::RestClient::Request).should_receive(:execute).and_yield('bar', nil, res)
        flexmock(res).should_receive(:content_length).and_return(0)

        # Speed up this test
        flexmock(subject).should_receive(:calculate_timeout).and_return(0)

        flexmock(ReposeDownloader.logger).should_receive(:info).once
        flexmock(ReposeDownloader.logger).should_receive(:error).never

        subject.download(attachment) do |response|
          response.should == 'bar'
        end
      end

      context "403: Forbidden" do
        let(:message) { "Forbidden" }
        let(:code)    { 403 }

        it_should_behave_like 'DownloadException'
      end

      context "404: Resource Not Found" do
        let(:message) { "Resource Not Found" }
        let(:code)    { 404 }

        it_should_behave_like 'DownloadException'
      end

      context "408: Request Timeout" do
        let(:exception) { nil }
        let(:message) { "Request Timeout" }
        let(:code)    { 408 }

        it_should_behave_like 'ConnectionException'
      end


      context "500: Internal Server Error" do
        let(:exception) { nil }
        let(:message)   { "Internal Server Error" }
        let(:code)      { 500 }

        it_should_behave_like 'ConnectionException'
      end

      context "Errno::ECONNREFUSED" do
        let(:exception) { Errno::ECONNREFUSED.new }

        it_should_behave_like 'ConnectionException'
      end

      context "Errno::ETIMEDOUT" do
        let(:exception) { Errno::ETIMEDOUT.new }

        it_should_behave_like 'ConnectionException'
      end

      context "SocketError" do
        let(:exception) { SocketError.new }

        it_should_behave_like 'ConnectionException'
      end
    end

    context :parse_exception_message do
      it 'should parse exceptions' do
        e = SocketError.new
        subject.send(:parse_exception_message, e).should == ["SocketError"]
      end

      it 'should parse a single RequestBalancer exception' do
        e = RightSupport::Net::NoResult.new("Request failed after 2 tries to 1 endpoint: ('174.129.36.231' => [SocketError])")
        subject.send(:parse_exception_message, e).should == ["SocketError"]
      end

      it 'should parse multiple RequestBalancer exceptions' do
        e = RightSupport::Net::NoResult.new("Request failed after 2 tries to 2 endpoints: ('174.129.36.231' => [SocketError], " +
                                            "'174.129.37.65' => [RestClient::InternalServerError, RestClient::ResourceNotFound])")
        subject.send(:parse_exception_message, e).should == ["SocketError", "RestClient::InternalServerError", "RestClient::ResourceNotFound"]
      end
    end

    context :balancer do
      let(:balancer) { subject.send(:balancer) }

      it 'should return a RequestBalancer' do
        balancer.should be_a(RightSupport::Net::RequestBalancer)
      end

      it 'should retry 5 times' do
        balancer.inspect
        balancer.instance_eval('@options[:retry]').should == 5
      end

      it 'should try all IPs of hostname 1, then all IPs of hostname 2, etc' do
        hostnames = ["hostname1", "hostname2"]
        ips = { "1.1.1.1" => "hostname2",
          "2.2.2.2" => "hostname1",
          "3.3.3.3" => "hostname2",
          "4.4.4.4" => "hostname1"
        }
        ordered_hosts = ["hostname1", "hostname1", "hostname2", "hostname2"]

        subject.instance_variable_set(:@hostnames, hostnames)
        subject.instance_variable_set(:@ips, ips)

        balancer.request do |endpoint|
          if ordered_hosts.length > 0
            ips[endpoint].should == ordered_hosts.shift
            Net::HTTPInternalServerError.new('1.1', 'RequestTimeout', '408').value
          end
        end
      end
    end

    context :calculate_timeout do
      it 'should return a doubly increasing timeout' do
        previous_timeout = 60

        (1..3).each do |i|
          timeout = subject.send(:calculate_timeout, i)
          timeout.should == previous_timeout * 2

          previous_timeout = timeout
        end
      end

      it 'should never return a timeout greater than RETRY_BACKOFF_MAX' do
        subject.send(:calculate_timeout, ReposeDownloader::RETRY_MAX_ATTEMPTS).should == (2**ReposeDownloader::RETRY_BACKOFF_MAX) * 60
      end
    end

    context :get_ca_file do
      it 'should return a certificate authority' do
        subject.send(:get_ca_file).should be_a(String)
      end
    end

    context :get_http_client do
      let(:proxy) { 'http://username:password@proxy.rightscale.com' }

      it 'should return an instance of RestClient with no proxy if one is not specified' do
        client = subject.send(:get_http_client)
        client.should == RestClient::Request
        RestClient.proxy.should be_nil
      end

      it 'should return an instance of RestClient with a proxy if one is specified' do
        ENV['HTTPS_PROXY'] = proxy
        client = subject.send(:get_http_client)
        client.should == RestClient::Request
        RestClient.proxy.should == proxy
      end
    end

    context :sanitize_resource do
      it 'should sanitize attachments' do
        subject.send(:sanitize_resource, attachment).should == '98c272b109c592ae4d4670d3279c8df282d6e681'
      end

      it 'should sanitize cookbooks' do
        subject.send(:sanitize_resource, cookbook).should == '98c272b109c592ae4d4670d3279c8df282d6e681'
      end
    end

    context :scale do
      it 'should calculate scales' do
        subject.send(:scale, 0).should == [0, 'B']
        subject.send(:scale, 1023).should == [1023, 'B']
        subject.send(:scale, 1024).should == [1, 'KB']
        subject.send(:scale, 1024**2 - 1).should == [(1024**2 - 1) / 1024, 'KB']
        subject.send(:scale, 1024**2).should == [1, 'MB']
        subject.send(:scale, 1024**3 - 1).should == [(1024**3 - 1) / 1024**2, 'MB']
        subject.send(:scale, 1024**3).should == [1, 'GB']
      end
    end
  end
end
