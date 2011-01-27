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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper.rb'))

shared_examples_for 'not in cloud' do
  it 'does not populate the cloud mash' do
    @ohai._require_plugin(@cloud.to_s)
    @ohai[@cloud].should be_nil
  end
end

shared_examples_for 'cloud file refers to another cloud' do
  before(:each) do
      flexmock(RightScale::CloudUtilities).should_receive(:is_cloud?).and_return(false)
  end

  it_should_behave_like 'not in cloud'
end

shared_examples_for 'can query metadata and user data' do
  before(:each) do
    @data = {'item_one' => "value.one",
             'item_two' => "value_two",
             'array_type' => ['one', 'two'],
             'L1_L2_item_1' => "L2-one",
             'L1_L2_item_2' => "L2two",
             'L1_L2_item_3' => "L2/three"}

    mock_mash = Mash.new(@data)
    if @root_keys.nil?
      flexmock(RightScale::CloudUtilities).should_receive(:metadata).with(@metadata_url).and_return(mock_mash)
    else
      flexmock(RightScale::CloudUtilities).should_receive(:metadata).with(@metadata_url, @root_keys).and_return(mock_mash)
    end

    flexmock(RightScale::CloudUtilities).should_receive(:userdata).with(@userdata_url).and_return('some user data')

    @ohai._require_plugin(@cloud.to_s)
    end

    it 'mash is defined' do
      @ohai[@cloud].should_not be_nil
    end

    it 'mash has simple meta data' do
      @ohai[@cloud]['item_one'].should == "value.one"
      @ohai[@cloud]['item_two'].should == "value_two"
    end

    it 'mash has array meta data' do
      @ohai[@cloud]['array_type'].should == ['one', 'two']
    end

    it 'mash has flattened hierarchical data' do
      @ohai[@cloud]['L1_L2_item_1'].should == "L2-one"
      @ohai[@cloud]['L1_L2_item_2'].should == "L2two"
      @ohai[@cloud]['L1_L2_item_3'].should == "L2/three"
    end

    it 'should have userdata' do
      @ohai[@cloud][:userdata].should == "some user data"
    end
end
