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

  before(:each) do
    @old_SL_METADATA_DIR = ::Ohai::Mixin::SoftlayerMetadata::SL_METADATA_DIR
    ::Ohai::Mixin::SoftlayerMetadata.const_set('SL_METADATA_DIR', File.expand_path('../fixtures/softlayer', __FILE__))
  end

  after(:each) do
    Object.const_set('SL_METADATA_DIR', @old_SL_METADATA_DIR)
  end


  context 'fetch_metadata' do
    it "read meta_data.json" do
      metadata = mixin.fetch_metadata
      metadata.should_not be_nil
      metadata['files'].should == [[]]
      metadata['hostname'].should == '18ea2e0371db742'
      metadata['name'].should == '18ea2e0371db742'
      metadata['domain'].should == 'rightscale.com'
      metadata['meta'].should == { 'dsmode' => 'net'}
      metadata['uuid'].should == '47ae373d-79e1-9292-24cf-25d09db4bcdc'
      metadata['local_ipv4'].should == '10.84.80.195'
      metadata['public_ipv4'].should == '75.126.0.235'
    end
  end

end