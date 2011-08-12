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

describe RightScale::CloudUtilities do
  before(:each) do
    @ohai = Ohai::System.new
    flexmock(@ohai).should_receive(:require_plugin).and_return(true)
  end

  context '#has_mac?' do
    before(:each) do
      @ohai[:network] = {:interfaces => {:eth0 => {}}}
    end

    it 'that matches' do
      @ohai[:network][:interfaces][:eth0][:arp] = {"1.1.1.1"=>"ee:ee:ee:ee:ee:ee"}
      RightScale::CloudUtilities.has_mac?(@ohai, "ee:ee:ee:ee:ee:ee").should be_true
    end

    it 'that does not match' do
      @ohai[:network][:interfaces][:eth0][:arp] = {"1.1.1.1"=>"ff:ff:ff:ff:ff:ff"}
      RightScale::CloudUtilities.has_mac?(@ohai, "ee:ee:ee:ee:ee:ee").should be_false
    end
  end

  context '#can_contact_metadata_server?' do
    it 'server responds' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::EINPROGRESS)
      flexmock(Socket).should_receive(:new).and_return(t)

      flexmock(IO).should_receive(:select).and_return([[], [1], []])

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_true
    end

    it 'fails because server responds with nothing' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::EINPROGRESS)
      flexmock(Socket).should_receive(:new).and_return(t)

      flexmock(IO).should_receive(:select).and_return([[], nil, []])

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_false
    end

    it 'fails to connect to server' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock)
      flexmock(Socket).should_receive(:new).and_return(t)

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_false
    end

    it 'fails because of a system error' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::ENOENT)
      flexmock(Socket).should_receive(:new).and_return(t)

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_false
    end
  end

  context '#ip_for_interface' do
    it 'retrieves the appropriate ip address for a given interface' do
      @ohai[:network] = {:interfaces => {"eth0" => {"addresses" => {
              "ffff::111:fff:ffff:11" => {
                      "scope"=> "Link",
                      "prefixlen"=> "64",
                      "family"=> "inet6"
              },
              "ff:ff:ff:ff:ff:ff" => {
                      "family"=> "lladdr"
              },
              "1.1.1.1" => {
                      "broadcast" => "1.1.1.255",
                      "netmask" => "255.255.255.0",
                      "family" => "inet"
              }}}}}

      RightScale::CloudUtilities.ip_for_interface(@ohai, :eth0).should == "1.1.1.1"
    end

    it 'returns nothing when no network mash exists' do
      @ohai[:network] = nil
      RightScale::CloudUtilities.ip_for_interface(@ohai, :eth1).should be_nil
    end

    it 'returns nothing when no interfaces are defined' do
      @ohai[:network] = {}
      RightScale::CloudUtilities.ip_for_interface(@ohai, :eth1).should be_nil
    end

    it 'returns nothing when there are no addresses on a given interface' do
      @ohai[:network] = {:interfaces => {"eth1" => {}}}
      RightScale::CloudUtilities.ip_for_interface(@ohai, :eth1).should be_nil
    end
  end

  context '#ip_for_windows_interface' do
    it 'retrieves the appropriate ip address for a given interface' do
      @ohai[:network] = {:interfaces => {"0x1"=> {"addresses"=>
              {"1.1.1.1"=>
                      {"netmask"=>"255.255.255.0",
                       "broadcast"=>"1.1.1.255",
                       "family"=>"inet"},
               "10:10:10:10:10:0"=>{"family"=>"lladdr"}},
                                                  "type"=>"Ethernet 802.3",
                                                  "instance"=>
                                                          {"system_creation_class_name"=>"Win32_ComputerSystem",
                                                           "net_connection_id"=>"public"},
                                                  "encapsulation"=>"Ethernet",
                                                  "configuration"=>
                                                          {"ip_enabled"=>true,
                                                           "ip_address"=>["1.1.1.1"]}}}}

      RightScale::CloudUtilities.ip_for_windows_interface(@ohai, 'public').should == "1.1.1.1"
    end

    it 'returns nothing when no network mash exists' do
      @ohai[:network] = nil
      RightScale::CloudUtilities.ip_for_windows_interface(@ohai, 'public').should be_nil
    end

    it 'returns nothing when no interfaces are defined' do
      @ohai[:network] = {}
      RightScale::CloudUtilities.ip_for_windows_interface(@ohai, 'public').should be_nil
    end

    it 'returns nothing when there are no addresses on a given interface' do
      @ohai[:network] = {:interfaces => {"0xC" => {}}}
      RightScale::CloudUtilities.ip_for_windows_interface(@ohai, 'public').should be_nil
    end
  end

end
