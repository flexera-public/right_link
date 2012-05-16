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
  describe AttachmentProxyDownloader do
    let(:hostname) { 'repose9.rightscale.com' }

    class AttachmentProxyDownloader
      def test_get_http_client
        get_http_client
      end
    end

    context :get_http_client do
      let(:proxy) { 'http://username:password@proxy.rightscale.com' }

      it 'should use a proxy if a proxy is present' do
        flexmock(Socket).should_receive(:getaddrinfo) \
          .with(hostname, 443, Socket::AF_INET, Socket::SOCK_STREAM, Socket::IPPROTO_TCP) \
          .and_return([["AF_INET", 443, "ec2-174-129-36-231.compute-1.amazonaws.com", "174.129.36.231", 2, 1, 6], ["AF_INET", 443, "ec2-174-129-37-65.compute-1.amazonaws.com", "174.129.37.65", 2, 1, 6]])

        ENV['http_proxy'] = proxy
        downloader = AttachmentProxyDownloader.new(hostname)
        client = downloader.test_get_http_client

        client.should == RestClient
        client.proxy.should == proxy
      end
    end
  end
end
