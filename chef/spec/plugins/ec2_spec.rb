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

describe Ohai::System, " plugin ec2" do
  before(:each) do
    # configure ohai for RightScale
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)

    @cloud = :ec2
  end

  context 'when not in the ec2 cloud' do
    context 'because the mac address does not match' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
        flexmock(RightScale::CloudUtilities).should_receive(:has_mac?).with(@ohai, "fe:ff:ff:ff:ff:ff").and_return(false)
        flexmock(RightScale::CloudUtilities).should_receive(:can_contact_metadata_server?).never
      end

      it_should_behave_like 'not in cloud'
    end

    context 'because the metadata service does not respond' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
        flexmock(RightScale::CloudUtilities).should_receive(:has_mac?).with(@ohai, "fe:ff:ff:ff:ff:ff").and_return(true)
        flexmock(RightScale::CloudUtilities).should_receive(:can_contact_metadata_server?).with("169.254.169.254", 80).and_return(false)
      end

      it_should_behave_like 'not in cloud'
    end

    context 'because cloud file refers to another cloud' do
      it_should_behave_like 'cloud file refers to another cloud'
    end
  end

  context 'when in the ec2 cloud' do
    before(:each) do
      @metadata_url = "http://169.254.169.254/2008-02-01/meta-data"
      @userdata_url = "http://169.254.169.254/2008-02-01/user-data"

      flexmock(RightScale::CloudUtilities).should_receive(:is_cloud?).and_return(true)
      flexmock(RightScale::CloudUtilities).should_receive(:can_contact_metadata_server?).with("169.254.169.254", 80).and_return(true)
    end

    it_should_behave_like 'can query metadata and user data'

  end
end
