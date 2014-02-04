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
require 'tempfile'

describe Ohai::System, ' plugin azure' do

  before(:each) do
    flexmock(::RightScale::AgentConfig).should_receive(:cache_dir).and_return(Dir.mktmpdir)
    # configure ohai for RightScale
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
    @ohai._require_plugin("hostname")
  end

  # Provide only success scenario, becuase it will be changed in RL 6.1
  it 'populate azure node with required attributes' do
    flexmock(@ohai).should_receive(:hint?).with('azure').and_return({}).once
    flexmock(@ohai).should_receive(:tcp_test_ssh).and_yield.once
    flexmock(@ohai).should_receive(:tcp_test_winrm).and_yield.once
    flexmock(@ohai).should_receive(:query_whats_my_ip).and_return('1.2.3.4').once
    @ohai['hostname'] = 'my_hostname'
    @ohai._require_plugin("azure")
    @ohai[:azure].should_not be_nil
    @ohai[:azure]['vm_name'].should == 'my_hostname'
    @ohai[:azure]['public_fqdn'].should == 'my_hostname.cloudapp.net'
    @ohai[:azure]['public_ssh_port'].should == 22
    @ohai[:azure]['public_winrm_port'].should == 5985
    @ohai[:azure]['public_ip'].should == '1.2.3.4'
  end

end
