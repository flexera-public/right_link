#
# Copyright (c) 2009-2012 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'instance', 'cook'))

module RightScale
  describe ReposeDownloader do

    before(:each) do
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "ec2-174-129-36-231.compute-1.amazonaws.com", "174.129.36.231", 2, 1, 6], ["AF_INET", 443, "ec2-174-129-37-65.compute-1.amazonaws.com", "174.129.37.65", 2, 1, 6]])
    end

    let(:hostname) { 'repose9.rightscale.com' }
    subject { ReposeDownloader.new([hostname]) }

    context :resolve do
      it 'should resolve hostnames into IP addresses' do
        subject.send(:resolve, hostname).should == { "174.129.36.231" => hostname, "174.129.37.65" => hostname }
      end
    end

    context :parse_resource do
      it 'should parse resources correctly' do
        subject.send(:parse_resource, "https://#{hostname}:443/scope/resource").should == "scope/resource"
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
      it 'should download' do
        subject.download('test', 'destination')
        subject.size.should == 0
        subject.speed.should == 0.0
        subject.sanitized_resource.should == 'test'
      end
    end

    context :parse do
      it 'should parse exceptions' do
        e = SocketError.new
        subject.send(:parse, e).should == "SocketError"
      end

      it 'should parse RequestBalancer exceptions' do
        e = RightSupport::Net::NoResult.new('RequestBalancer: No available endpoints from ["174.129.36.231", "174.129.37.65"]! Exceptions: SocketError')
        subject.send(:parse, e).should == "SocketError"
      end
    end

    context :balancer do
      it 'should return a RequestBalancer' do
        subject.send(:balancer).should be_a(RightSupport::Net::RequestBalancer)
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
        client.should == RestClient
        client.proxy.should be_nil
      end

      it 'should return an instance of RestClient with a proxy if one is specified' do
        ENV['HTTPS_PROXY'] = proxy
        client = subject.send(:get_http_client)
        client.should == RestClient
        client.proxy.should == proxy
      end
    end

    context :sanitize_resource do
      it 'should sanitize the resource' do
        subject.send(:sanitize_resource, 'scope/resource?query_string').should == 'scope/resource'
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
