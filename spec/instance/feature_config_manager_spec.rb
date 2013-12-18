#
# Copyright (c) 2013 RightScale Inc
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

require File.join(File.dirname(__FILE__), 'spec_helper')

module RightScale
  describe FeatureConfigManager do
    subject { RightScale::FeatureConfigManager.instance }
    let (:test_data) { { "motd"=>{"update"=>false},
                         "decommission"=>{"timeout"=>100},
                         "package_repositories"=>{"freeze"=>true} } }

    context "#get_value" do
      it "should return value from features.yml" do
        flexmock(File).should_receive(:exists?).with(FeatureConfigManager::CONFIG_YAML_FILE).and_return(true)
        flexmock(YAML).should_receive(:load_file).and_return(test_data)
        subject.get_value("motd_update").should == test_data["motd"]["update"]
      end

      it "should return nil if values doesn't exist" do
        flexmock(File).should_receive(:exists?).with(FeatureConfigManager::CONFIG_YAML_FILE).and_return(false)
        subject.get_value("motd_update").should be_nil
      end
    end
    context "#set_value" do
      it "should set value and store it in features.yml" do
        flexmock(File).should_receive(:exists?).with(FeatureConfigManager::CONFIG_YAML_FILE).and_return(true)
        flexmock(File).should_receive(:open).with(FeatureConfigManager::CONFIG_YAML_FILE, "w", Proc).and_return(true)
        flexmock(YAML).should_receive(:load_file).and_return(test_data)
        subject.set_value("motd_update", false)
        subject.get_value("motd_update").should == false
      end
    end
    context "#list" do
      it "should return hash of values stored in features.yml" do
        flexmock(File).should_receive(:exists?).with(FeatureConfigManager::CONFIG_YAML_FILE).and_return(true)
        flexmock(YAML).should_receive(:load_file).and_return(test_data)
        subject.list.to_yaml.should == test_data.to_yaml
      end

      it "should return empty hash if features.yml doesn't exist" do
        flexmock(File).should_receive(:exists?).with(FeatureConfigManager::CONFIG_YAML_FILE).and_return(false)
        subject.list.to_yaml.should == {}.to_yaml
      end
    end
  end
end
