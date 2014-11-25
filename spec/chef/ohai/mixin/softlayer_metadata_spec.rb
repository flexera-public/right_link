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

  before(:each) do
    temp_dir = Dir.mktmpdir
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(temp_dir)
    # configure ohai for RightScale
    ::Ohai::Config[:hints_path] = [File.join(temp_dir,"ohai","hints")]
    RightScale::OhaiSetup.configure_ohai
  end

  let(:mixin) {
    mixin = Object.new.extend(::Ohai::Mixin::SoftlayerMetadata)
    mixin
  }

  def make_request(item)
    "/rest/v3.1/SoftLayer_Resource_Metadata/#{item}"
  end

  def make_res(body)
    flexmock("response", {:body => body, :code => "200"})
  end


  context 'fetch_metadata' do
    it "raise an Exception on any query errors" do
      flexmock(::Ohai::Log).should_receive(:error).at_least.once
      http_mock = flexmock('http', {:ssl_version= => true, :use_ssl= => true, :ca_file= => true})
      http_mock.should_receive(:get).and_raise(Exception.new("API return fake error"))
      flexmock(::Net::HTTP).should_receive(:new).with('api.service.softlayer.com', 443).and_return(http_mock)
      mixin.fetch_metadata.should_not be_nil
    end

    it "query api service" do
      http_mock = flexmock('http', {:ssl_version= => true, :use_ssl= => true, :ca_file= => true})
      flexmock(::Net::HTTP).should_receive(:new).with('api.service.softlayer.com', 443).and_return(http_mock)

      http_mock.should_receive(:get).with(make_request('getFullyQualifiedDomainName.txt')).and_return(make_res('abc.host.org')).once
      http_mock.should_receive(:get).with(make_request('getPrimaryBackendIpAddress.txt')).and_return(make_res('10.0.1.10')).once
      http_mock.should_receive(:get).with(make_request('getPrimaryIpAddress.txt')).and_return(make_res('8.8.8.8')).once
      http_mock.should_receive(:get).with(make_request('getId.txt')).and_return(make_res('1111')).once
      http_mock.should_receive(:get).with(make_request('getDatacenter.txt')).and_return(make_res('dal05')).once


      metadata = mixin.fetch_metadata
      metadata.should_not be_nil
      metadata["public_fqdn"].should == 'abc.host.org'
      metadata["local_ipv4"].should == '10.0.1.10'
      metadata["instance_id"].should == '1111'
      metadata["region"].should == 'dal05'
      metadata["public_ipv4"].should == '8.8.8.8'
    end
  end
end

