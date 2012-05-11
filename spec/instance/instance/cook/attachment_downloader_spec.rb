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
RightSupport::Log::Mixin.default_logger = Logger.new(STDOUT)
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'instance', 'cook'))

module RightScale
  describe AttachmentDownloader do
    let(:hostname)   { 'repose9.rightscale.com' }
    let(:resource)   { 'https://repose9.rightscale.com/attachments/1/foo?query=string' }

    before(:each) do
      flexmock(Socket).should_receive(:getaddrinfo) \
          .with(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "ec2-174-129-36-231.compute-1.amazonaws.com", "174.129.36.231", 2, 1, 6], ["AF_INET", 443, "ec2-174-129-37-65.compute-1.amazonaws.com", "174.129.37.65", 2, 1, 6]])
    end

    context :download do
      it 'should fail to download with a DownloadException without retrying if access to the resource is forbidden' do
        http_client = flexmock('http_client')
        http_client.should_receive(:request).and_raise(RestClient::Forbidden.new(nil, 403))
        flexmock(RightSupport::Net::HTTPClient).should_receive(:new).and_return(http_client)

        downloader = AttachmentDownloader.new(hostname)
        flexmock(AttachmentDownloader.logger).should_receive(:info).once
        flexmock(AttachmentDownloader.logger).should_receive(:error).twice

        lambda { downloader.download(resource) }.should raise_error(RightScale::AttachmentDownloader::DownloadException)
      end

      it 'should fail to download with a DownloadException without retrying if the resource does not exist' do
        http_client = flexmock('http_client')
        http_client.should_receive(:request).and_raise(RestClient::ResourceNotFound.new(nil, 404))
        flexmock(RightSupport::Net::HTTPClient).should_receive(:new).and_return(http_client)

        downloader = AttachmentDownloader.new(hostname)
        flexmock(AttachmentDownloader.logger).should_receive(:info).once
        flexmock(AttachmentDownloader.logger).should_receive(:error).twice

        lambda { downloader.download(resource) }.should raise_error(RightScale::AttachmentDownloader::DownloadException)
      end

      it 'should fail to download if no endpoints respond' do
        http_client = flexmock('http_client')
        http_client.should_receive(:request).and_raise(Errno::ECONNREFUSED.new('Connection refused - connect(2)'))
        flexmock(RightSupport::Net::HTTPClient).should_receive(:new).and_return(http_client)

        downloader = AttachmentDownloader.new(hostname)
        flexmock(AttachmentDownloader.logger).should_receive(:info).twice
        flexmock(AttachmentDownloader.logger).should_receive(:error).times(4)

        lambda { downloader.download(resource) }.should raise_error(RightScale::AttachmentDownloader::ConnectionException)
      end

      it 'should download an attachment' do
        http_client = flexmock('http_client')
        http_client.should_receive(:request).and_yield('bar')
        flexmock(RightSupport::Net::HTTPClient).should_receive(:new).and_return(http_client)

        downloader = AttachmentDownloader.new(hostname)
        flexmock(AttachmentDownloader.logger).should_receive(:info).once
        flexmock(AttachmentDownloader.logger).should_receive(:error).never

        downloader.download(resource) do |response|
          response.should == 'bar'
        end
      end
    end

    context :sanitize_resource do
      let(:downloader) { AttachmentDownloader.new(hostname) }

      class AttachmentDownloader
        def test_sanitize_resource(resource)
          sanitize_resource(resource)
        end
      end

      it 'should return the \'resource\' portion of the uri' do
        downloader.test_sanitize_resource(resource).should == 'foo'
      end
    end

    context :parse do
      let(:downloader) { AttachmentDownloader.new(hostname) }

      class AttachmentDownloader
        def test_parse(exception)
          parse(exception)
        end
      end

      it 'should return an array of exceptions' do
        exception = RestClient::Forbidden.new(nil, 403)

        downloader.test_parse(exception).should == "RestClient::Forbidden"
      end

      it 'should return an array of exceptions from RequestBalancer' do
        exception = RightSupport::Net::NoResult.new('No available endpoints from ["174.129.36.231", "174.129.37.65"]! Exceptions: RestClient::InternalServerError, RestClient::ResourceNotFound')

        downloader.test_parse(exception).should == "RestClient::InternalServerError, RestClient::ResourceNotFound"
      end
    end
  end
end
