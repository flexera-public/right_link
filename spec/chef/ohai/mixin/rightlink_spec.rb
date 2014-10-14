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
require 'chef/ohai/mixin/rightlink'

describe ::Ohai::Mixin::RightLink do

  context 'CloudUtilities' do
    subject { Object.new.extend(::Ohai::Mixin::RightLink::CloudUtilities) }
    let(:network) {
      {
        :interfaces => {
          :lo   => { :addresses => { "127.0.0.1" => { 'family' => 'inet' } }, :flags => ["LOOPBACK"] },
          :eth0 => { :addresses => { "50.23.101.210" => { 'family' => 'inet' } }, :flags => [] },
          :eth1 => { :addresses => { "192.168.0.1" => { 'family' => 'inet' } }, :flags => []}
        }
      }
    }
    it 'should query instance ip'

    context '#private_ipv4?' do
      it 'returns true for private ipv4' do
        subject.private_ipv4?("192.168.0.1").should be_true
      end

      it 'returns false for public ipv4' do
        subject.private_ipv4?("8.8.8.8").should_not be_true
      end
    end

    context '#ips' do
      it 'returns list of ips of all network interfaces' do
        subject.ips(network).should_not be_empty
      end

      it "doesn't include localhost ip to list" do
        subject.ips(network).should_not include "127.0.0.1"
      end
    end

    context '#public_ips' do
      it 'returns list of public ips' do
        subject.public_ips(network).any? { |ip| subject.private_ipv4?(ip) }.should_not be true
      end
    end

    context '#private_ips' do
      it 'returns list of private ips' do
        subject.private_ips(network).all? { |ip| subject.private_ipv4?(ip) }.should be true
      end
    end
  end
end

