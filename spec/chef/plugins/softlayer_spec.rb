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
require 'tempfile'

describe Ohai::System, ' plugin softlayer' do

  before(:each) do
    temp_dir = Dir.mktmpdir
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(temp_dir)
    # configure ohai for RightScale
    ::Ohai::Config[:hints_path] = [File.join(temp_dir,"ohai","hints")]
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:depends).and_return(true)

  end

  it 'create softlayer if hint file exists' do
    flexmock(@ohai).should_receive(:hint?).with('softlayer').and_return({}).once
    @ohai._require_plugin("softlayer")
    @ohai[:softlayer].should_not be_nil
  end

  it "not create softlayer if hint file doesn't exists" do
    flexmock(@ohai).should_receive(:hint?).with('softlayer').and_return(nil).once
    @ohai._require_plugin("softlayer")
    @ohai[:softlayer].should be_nil
  end

  it 'populate softlayer node with required attributes' do

    fetched_metadata = {
      'local_ipv4'  => '10.84.80.195',
      'public_ipv4' => '75.126.0.235',
      'files'       => [[]],
      'hostname'    => '18ea2e0371db742',
      'name'        => '18ea2e0371db742',
      'domain'      => 'rightscale.com',
      "meta"        => { 'dsmode' => 'net'},
      'uuid'        => '47ae373d-79e1-9292-24cf-25d09db4bcdc'
    }

    flexmock(@ohai).should_receive(:hint?).with('softlayer').and_return({}).once
    flexmock(@ohai).should_receive(:fetch_metadata).and_return(fetched_metadata)
    @ohai._require_plugin("softlayer")
    @ohai[:softlayer]['local_ipv4'].should == '10.84.80.195'
    @ohai[:softlayer]['public_ipv4'].should == '75.126.0.235'
    @ohai[:softlayer]['files'].should == [[]]
    @ohai[:softlayer]['hostname'].should == '18ea2e0371db742'
    @ohai[:softlayer]['name'].should == '18ea2e0371db742'
    @ohai[:softlayer]['domain'].should == 'rightscale.com'
    @ohai[:softlayer]['meta'].should == { 'dsmode' => 'net'}
    @ohai[:softlayer]['uuid'].should == '47ae373d-79e1-9292-24cf-25d09db4bcdc'

  end
end
