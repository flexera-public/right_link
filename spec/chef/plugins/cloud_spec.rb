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

describe Ohai::System, ' plugin cloud' do

  before(:each) do
    # configure ohai for RightScale
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new

    @expected_public_ip = "1.1.1.1"
    @expected_private_ip = "10.252.252.10"
  end

  shared_examples_for 'generic cloud' do
    context 'contains generic settings' do
      before(:each) do
        @cloud_instance = flexmock('fake_cloud', :name=> @expected_cloud)
        @cloud_instance.should_receive(:build_metadata).with(:cloud_metadata).and_return(@metadata)
        @cloud_instance.should_receive(:build_metadata).with(:user_metadata).and_return(@userdata)
        @cloud_instance.should_receive(:update_details).and_return(@additionaldata)
        @cloud_factory = flexmock('fake_factory')
        @cloud_factory.should_receive(:create).and_return(@cloud_instance)
        flexmock(RightScale::CloudFactory).should_receive(:instance).and_return(@cloud_factory)

        flexmock(@ohai).should_receive(:require_plugin).and_return(true)

        @ohai._require_plugin("cloud")
      end

      it 'should not define other cloud plugins' do
        %w{ ec2 rackspace cloudstack eucalyptus }.select { |cloud| cloud != @expected_cloud }.each do |cloud_name|
          @ohai[cloud_name.to_sym].should be_nil
        end
      end

      it 'should populate cloud provider' do
        @ohai[:cloud][:provider].should == @expected_cloud
      end

      it 'should populate cloud public ip' do
        @ohai[:cloud][:public_ips].first.should == @expected_public_ip
      end

      it 'should populate cloud private ip' do
        @ohai[:cloud][:private_ips].first.should == @expected_private_ip
      end
    end
  end

  context 'no cloud' do
    before :each do
      flexmock(@ohai).should_receive(:require_plugin).and_return(true)

      cloud_file_path = File.normalize_path(File.join(RightScale::Platform.filesystem.right_scale_state_dir, 'cloud'))
      flexmock(File).should_receive(:read).with(cloud_file_path).and_return('no_cloud')
      flexmock(File).should_receive(:file?).with(cloud_file_path).and_return(true)

      @ohai._require_plugin("cloud")
    end

    it 'should NOT populate the cloud data' do
      @ohai[:cloud].should be_nil
    end
  end

  context 'on EC2' do
    before(:each) do
      @expected_cloud = 'ec2'
      @metadata = {:"public-ipv4" => @expected_public_ip, :"local-ipv4" => @expected_private_ip}
      @userdata = {}
      @additionaldata = {}
    end

    it_should_behave_like 'generic cloud'
  end

  context 'on Rackspace' do
    before(:each) do
      @expected_cloud = "rackspace"
      @metadata = ""
      @userdata = ""
      @additionaldata = {:public_ip => @expected_public_ip, :private_ip => @expected_private_ip}
    end

    it_should_behave_like 'generic cloud'
  end

  context 'on Eucalyptus' do
    before(:each) do
      @expected_cloud = "eucalyptus"
      @metadata = {:"public-ipv4" => @expected_public_ip, :"local-ipv4" => @expected_private_ip}
      @userdata = {}
      @additionaldata = {}
    end

    it_should_behave_like 'generic cloud'
  end

  context 'on cloudstack' do
    before(:each) do
      @expected_cloud = "cloudstack"
      @metadata = {:"public-ipv4" => @expected_public_ip, :"local-ipv4" => @expected_private_ip}
      @userdata = {}
      @additionaldata = {}
    end

    it_should_behave_like 'generic cloud'
  end
end
