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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper.rb'))
require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper.rb'))
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
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
    @softlayer = get_plugin("softlayer", @ohai)
    @network = {
        :interfaces => {
            :lo   => { :flags => ["LOOPBACK"] },
            :eth0 => { :flags => [], :addresses => { "50.23.101.210" => { 'family' => 'inet' } } },
            :eth1 => { :flags => [], :addresses => { "192.168.0.1" => { 'family' => 'inet' } } }
        }
    }
  end

  it 'create softlayer if hint file exists' do
    flexmock(@softlayer).should_receive(:hint?).with('softlayer').and_return({}).once
    flexmock(@softlayer).should_receive(:network).and_return(@network)
    @softlayer.run
    @ohai[:softlayer].should_not be_nil
  end

  it "not create softlayer if hint file doesn't exists" do
    flexmock(@softlayer).should_receive(:hint?).with('softlayer').and_return(nil).once
    @softlayer.run
    @ohai[:softlayer].should be_nil
  end

  it 'populate softlayer node with required attributes' do
    flexmock(@softlayer).should_receive(:hint?).with('softlayer').and_return({}).once
    flexmock(@softlayer).should_receive(:network).and_return(@network)
    @softlayer.run
    @ohai[:softlayer]['local_ipv4'] = '50.23.101.210'
    @ohai[:softlayer]['public_ipv4'] = '192.168.0.1'
    @ohai[:softlayer]['private_ips'] = ['50.23.101.210']
    @ohai[:softlayer]['public_ips'] = ['192.168.0.1']
  end
end
