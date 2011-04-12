# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

require 'fileutils'
require File.normalize_path(File.join(File.dirname(__FILE__), 'chef_runner'))

module RightScaleTestPluginSpec
  TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "rightscale-test-plugin-spec-C6C7AFC5-94C4-4667-AFA8-46B9BAE7ED42"))
  TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
end

describe Ohai::System, " rightscale_test_plugin" do
  def create_cookbook
    RightScale::Test::ChefRunner.create_cookbook(
            RightScaleTestPluginSpec::TEST_TEMP_PATH,
            {
                    :echo_test_node_recipe => (
                    <<EOF
ruby 'test::echo_test_node_recipe' do
  test_value = node[:rightscale_test_plugin][:test_value]
  code \"puts \\\"test node value = \#\{test_value\}\\\"\\n\"
end
EOF
                    )
            }
    )
  end

  def cleanup
    (FileUtils.rm_rf(RightScaleTestPluginSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(RightScaleTestPluginSpec::TEST_TEMP_PATH)
  end

  it_should_behave_like 'generates cookbook for chef runner'
  it_should_behave_like 'mocks logging'

  it "should load custom ohai plugins" do
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
              RightScaleTestPluginSpec::TEST_COOKBOOKS_PATH,
              'test::echo_test_node_recipe') }
    runner.call.should be_true

    @logger.error_text.should be_empty
    @logger.info_text.should include("test node value = abc")
  end

end
