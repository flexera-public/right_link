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
      @ohai[:network] = {:interfaces => {:eth0 => {} } }
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

      flexmock(IO).should_receive(:select).and_return([[],[1],[]])

      RightScale::CloudUtilities.can_contact_metadata_server?("1.1.1.1", 80).should be_true
    end

    it 'fails because server responds with nothing' do
      t = flexmock("connection")
      flexmock(t).should_receive(:connect_nonblock).and_raise(Errno::EINPROGRESS)
      flexmock(Socket).should_receive(:new).and_return(t)

      flexmock(IO).should_receive(:select).and_return([[],nil,[]])

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

  context '#metadata' do
    before(:each) do
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/").and_return(flexmock("IO1", :read => "item-one\nitem_two\nL1/\narray-type"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/item-one").and_return(flexmock("IO2", :read => "value.one"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/item_two").and_return(flexmock("IO3", :read => "value_two"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/L1/").and_return(flexmock("IO4", :read => "L2-item-1\nL2-item-2\nL2-item-3"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/L1/L2-item-1").and_return(flexmock("IO5", :read => "L2-one"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/L1/L2-item-2").and_return(flexmock("IO6", :read => "L2two"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/L1/L2-item-3").and_return(flexmock("IO7", :read => "L2/three"))
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/meta-data/array-type").and_return(flexmock("IOn", :read => "one\ntwo"))
    end

    shared_examples_for 'has valid metadata' do
      it 'converts - in key name to _' do
        @data['item_one'].should == "value.one"
      end

      it 'retrieves simple value' do
        @data['item_two'].should == "value_two"
      end

      it 'retrieves array values' do
        @data['array_type'].should eql ['one', 'two']
      end

      it 'retrieves hierarchical values' do
        @data['L1_L2_item_1'].should == "L2-one"
        @data['L1_L2_item_2'].should == "L2two"
        @data['L1_L2_item_3'].should == "L2/three"
      end
    end

    context 'querying for root metadata' do
      before(:each) do
        @data = RightScale::CloudUtilities.metadata("http://1.1.1.1/the/meta-data")
      end

      it_should_behave_like 'has valid metadata'
    end

    context 'using predefined set of root metadata' do
      before(:each) do
        predefined_metadata = %w{item-one item_two L1/ array-type}

        @data = RightScale::CloudUtilities.metadata("http://1.1.1.1/the/meta-data", '', predefined_metadata)
      end

      it_should_behave_like 'has valid metadata'
    end
  end

  context '#userdata' do
    it 'retrieves user data' do
      flexmock(OpenURI).should_receive(:open_uri).with("http://1.1.1.1/the/user-data/").and_return(flexmock("IOn", :read => "a bunch of data, with\ninteresting, characters !.#=1$ to be left alone"))

      RightScale::CloudUtilities.userdata("http://1.1.1.1/the/user-data").should == "a bunch of data, with\ninteresting, characters !.#=1$ to be left alone"
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
                                                      } } } } }

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
      @ohai[:network] = {:interfaces => {"eth1" => {} } }
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
      @ohai[:network] = {:interfaces => {"0xC" => {} } }
      RightScale::CloudUtilities.ip_for_windows_interface(@ohai, 'public').should be_nil
    end
  end

  context '#cloud' do
    it 'cloud file does not exist' do
      flexmock(File).should_receive(:exist?).and_return(false)
      RightScale::CloudUtilities.cloud.should == :unknown
    end

    it 'cloud file contains a valid cloud' do
      flexmock(File).should_receive(:exist?).and_return(true)
      flexmock(File).should_receive(:read).and_return("acloud")
      RightScale::CloudUtilities.cloud.should == :acloud
    end
  end

  context '#is_cloud?' do
    it 'cloud matches expected cloud' do
      flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:acloud)
      RightScale::CloudUtilities.is_cloud?(:acloud).should be_true
    end

    it 'cloud does not match expected cloud' do
      flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:somecloud)
      RightScale::CloudUtilities.is_cloud?(:acloud).should be_false
    end

    it 'cloud is unknown no block' do
      flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
      RightScale::CloudUtilities.is_cloud?(:acloud).should be_true
    end

    it 'cloud is unknown false block' do
      flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
      RightScale::CloudUtilities.is_cloud?(:acloud){false}.should be_false
    end

    it 'cloud is unknown true block' do
      flexmock(RightScale::CloudUtilities).should_receive(:cloud).and_return(:unknown)
      RightScale::CloudUtilities.is_cloud?(:acloud){true}.should be_true
    end
  end
end
