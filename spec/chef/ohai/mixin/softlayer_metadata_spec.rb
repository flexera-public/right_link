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
require 'chef/ohai/mixin/softlayer_metadata'

describe ::Ohai::Mixin::SoftlayerMetadata do

  let(:mixin) {
    mixin = Object.new.extend(::Ohai::Mixin::SoftlayerMetadata)
    mixin
  }

  context 'fetch_metadata' do

    it "query api service" do
      http_mock = flexmock('http')
      http_mock.should_receive(:request).and_return do |request|
        response = flexmock('response')
        case request.path
          when /getFullyQualifiedDomainName\.txt$/
            response.should_receive(:body).and_return('abc.host.org')
          when /getPrimaryBackendIpAddress\.txt$/
            response.should_receive(:body).and_return('10.0.1.10')
          when /getPrimaryIpAddress\.txt$/
            response.should_receive(:body).and_return('8.8.8.8')
          else
            raise "unsupported request"
        end
        response
      end
      flexmock(::Net::HTTP).should_receive(:start).with('api.service.softlayer.com', 443, {:use_ssl => true}, Proc).and_yield(http_mock)
      metadata = mixin.fetch_metadata
      metadata.should_not be_nil
      metadata["public_fqdn"].should == 'abc.host.org'
      metadata["local_ipv4"].should == '10.0.1.10'
      metadata["public_ipv4"].should == '8.8.8.8'
    end
  end
end

