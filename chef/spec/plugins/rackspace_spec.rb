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

describe Ohai::System, " plugin rackspace" do
  before(:each) do
    # configure ohai for RightScale
    RightScale::OhaiSetup.configure_ohai

    # ohai to be tested
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)

    # test IPs
    @expected_public_ip = "1.1.1.1"
    @expected_private_ip = "10.252.252.10"
  end

  shared_examples_for 'not on the rackspace cloud' do
    shared_examples_for 'not in rackspace' do
      it 'does not populate the rackspace mash' do
        @ohai._require_plugin("rackspace")
        @ohai[:rackspace].should be_nil
      end
    end

    context 'neither the mac address or the kernel match' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:has_mac?).with(@ohai, "00:00:0c:07:ac:01").and_return(false)
        @ohai[:kernel] = {:release => "not-as-expected"}
      end

      it_should_behave_like 'not in rackspace'
    end
  end

  shared_examples_for 'on the rackspace cloud' do
    shared_examples_for 'is in rackspace' do
      before(:each) do
        @ohai._require_plugin("rackspace")
        @ohai._require_plugin("#{@ohai[:os]}::rackspace")
      end

      it 'rackspace is defined' do
        @ohai[:rackspace].should_not be_nil
      end

      it 'has a public ip' do
        @ohai[:rackspace][:public_ip].should == @expected_public_ip
      end

      it 'has a private ip' do
        @ohai[:rackspace][:private_ip].should == @expected_private_ip
      end
    end

    context 'mac matches' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
        flexmock(RightScale::CloudUtilities).should_receive(:has_mac?).with(@ohai, "00:00:0c:07:ac:01").and_return(true)
      end

      it_should_behave_like 'is in rackspace'
    end

    context 'kernel matches' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
        flexmock(RightScale::CloudUtilities).should_receive(:has_mac?).with(@ohai, "00:00:0c:07:ac:01").and_return(false)
        @ohai[:kernel] = {:release => "something-as-expected-rscloud"}
      end

      it_should_behave_like 'is in rackspace'
    end

    context 'cloud file refers to cloud' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:is_cloud?).and_return(true)
        flexmock(RightScale::CloudUtilities).should_receive(:has_mac?).never
      end

      it_should_behave_like 'is in rackspace'
    end
  end

  context 'when in a linux instance' do
    before(:each) do
      @ohai[:os] = 'linux'
    end

    context 'and not in the rackspace cloud' do
      it_should_behave_like 'not on the rackspace cloud'
    end

    context 'and is in the rackspace cloud' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:ip_for_interface).with(@ohai, :eth0).and_return(@expected_public_ip)
        flexmock(RightScale::CloudUtilities).should_receive(:ip_for_interface).with(@ohai, :eth1).and_return(@expected_private_ip)
      end

      it_should_behave_like 'on the rackspace cloud'
    end
  end

  context 'when on a windows instance' do
    before(:each) do
      @ohai[:os] = 'windows'
    end

    context 'and not in the rackspace cloud' do
      it_should_behave_like 'not on the rackspace cloud'
    end

    context 'and is in the rackspace cloud' do
      before(:each) do
        flexmock(RightScale::CloudUtilities).should_receive(:ip_for_windows_interface).with(@ohai, 'public').and_return(@expected_public_ip)
        flexmock(RightScale::CloudUtilities).should_receive(:ip_for_windows_interface).with(@ohai, 'private').and_return(@expected_private_ip)
      end

      it_should_behave_like 'on the rackspace cloud'
    end
  end
end
