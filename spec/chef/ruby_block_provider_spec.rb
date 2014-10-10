#
# Copyright (c) 2012 RightScale Inc
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
require File.normalize_path(File.join(File.dirname(__FILE__), 'chef_runner'))

module RubyBlockProviderSpec
  TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "ruby-block-provider-spec-71DF6DE46CAE3AB4BD297F0D3609C2DA"))
  TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)

  class CustomError < Exception; end
end

describe Chef::Provider::RubyBlock do

  def create_cookbook
    RightScale::Test::ChefRunner.create_cookbook(
      RubyBlockProviderSpec::TEST_TEMP_PATH,
      {
        :log_test_recipe => (<<EOF
ruby_block 'test::log_test_recipe' do
  block { ::Chef::Log.info("Logged stuff") }
end
EOF
        ), :explosion_test_recipe => (<<EOF
ruby_block 'test::explosion_test_recipe' do
  block do
    ::Chef::Log.info("Prepare to explode...")
    raise ::RubyBlockProviderSpec::CustomError.new("Something went horribly wrong!")
    ::Chef::Log.error("should not get here.")
  end
end
EOF
        )
      }
    )
  end

  def cleanup
    (FileUtils.rm_rf(RubyBlockProviderSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(RubyBlockProviderSpec::TEST_TEMP_PATH)
  end

  it_should_behave_like 'generates cookbook for chef runner'
  it_should_behave_like 'mocks logging'
  it_should_behave_like 'mocks state'
  it_should_behave_like 'mocks metadata'

  it "should write to log" do
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RubyBlockProviderSpec::TEST_COOKBOOKS_PATH,
        'test::log_test_recipe') }
    runner.call.should be_true
    log_should_be_empty(:error)
    log_should_contain_text(:info, 'Logged stuff')
  end

  it "should log line of recipe execution where exceptions are raised" do
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RubyBlockProviderSpec::TEST_COOKBOOKS_PATH,
        'test::explosion_test_recipe') }
    runner.should raise_exception(::RubyBlockProviderSpec::CustomError)
    # Chef v11+ sends all errors raised during recipe execution to the
    # chef formatters for display.
    log_should_contain_text(:debug, 'Something went horribly wrong!')
    log_should_contain_text(:info, 'Prepare to explode...')
  end

end
