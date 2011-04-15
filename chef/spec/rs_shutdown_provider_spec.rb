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

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), 'chef_runner'))

module RsShutdownProviderSpec
  TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "rs-shutdown-provider-spec-766FD646F47C7C62BD3AAFBDCA5BA574"))
  TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
end

describe Chef::Provider::RsShutdown do

  def create_cookbook
    RightScale::Test::ChefRunner.create_cookbook(
      RsShutdownProviderSpec::TEST_TEMP_PATH,
      {
        :reboot_deferred_recipe => (<<EOF
rs_shutdown 'test::reboot_deferred_recipe' do
  action :reboot
  immediately false
end
EOF
        ), :reboot_immediately_recipe => (<<EOF
rs_shutdown 'test::reboot_immediately_recipe' do
  action :reboot
  immediately true
end
EOF
        ), :stop_deferred_recipe => (<<EOF
rs_shutdown 'test::stop_deferred_recipe' do
  action :stop
end
EOF
        ), :stop_immediately_recipe => (<<EOF
rs_shutdown 'test::stop_immediately_recipe' do
  action :stop
  immediately true
end
EOF
        ), :terminate_deferred_recipe => (<<EOF
rs_shutdown 'test::terminate_deferred_recipe' do
  action :terminate
end
EOF
        ), :terminate_immediately_recipe => (<<EOF
rs_shutdown 'test::terminate_immediately_recipe' do
  action :terminate
  immediately true
end
EOF
        )
      }
    )
  end

  def cleanup
    (FileUtils.rm_rf(RsShutdownProviderSpec::TEST_TEMP_PATH) rescue nil) if File.directory?(RsShutdownProviderSpec::TEST_TEMP_PATH)
  end

  def log_contains(str_to_match)
    # remove newlines and spaces
    expected_message = Regexp.escape(str_to_match.gsub(/\s+/, ""))

    # un-escape the escaped regex strings
    expected_message.gsub!("\\.\\*", ".*")

    # should contain the expected exception
    @logger.info_text.gsub(/\s+/, "").should match(expected_message)
  end

  before(:each) do
    RightScale::RightLinkLog.level = :debug
  end

  it_should_behave_like 'generates cookbook for chef runner'
  it_should_behave_like 'mocks logging'
  it_should_behave_like 'mocks state'
  it_should_behave_like 'mocks cook'

  def update_mock_shutdown_request(level, immediately = nil)
    @mock_shutdown_request.level = level
    @mock_shutdown_request.immediately! if immediately
    return @mock_shutdown_request
  end

  it "should reboot deferred" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::REBOOT, false).
                         and_return(update_mock_shutdown_request(::RightScale::ShutdownManagement::REBOOT, false))
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::reboot_deferred_recipe') }
    runner.call.should be_true
    @logger.error_text.should == ""
  end

  it "should reboot immediately" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::REBOOT, true).
                         and_return(update_mock_shutdown_request(::RightScale::ShutdownManagement::REBOOT, true))
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::reboot_immediately_recipe') }
    runner.should raise_exception(RightScale::Test::ChefRunner::MockSystemExit)
    @logger.error_text.should == ""
  end

  it "should stop deferred" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::STOP, false).
                         and_return(update_mock_shutdown_request(::RightScale::ShutdownManagement::STOP, false))
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::stop_deferred_recipe') }
    runner.call.should be_true
    @logger.error_text.should == ""
  end

  it "should stop immediately" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::STOP, true).
                         and_return(update_mock_shutdown_request(::RightScale::ShutdownManagement::STOP, true))
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::stop_immediately_recipe') }
    runner.should raise_exception(RightScale::Test::ChefRunner::MockSystemExit)
    @logger.error_text.should == ""
  end

  it "should terminate deferred" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::TERMINATE, false).
                         and_return(update_mock_shutdown_request(::RightScale::ShutdownManagement::TERMINATE, false))
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::terminate_deferred_recipe') }
    runner.call.should be_true
    @logger.error_text.should == ""
  end

  it "should terminate immediately" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::TERMINATE, true).
                         and_return(update_mock_shutdown_request(::RightScale::ShutdownManagement::TERMINATE, true))
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::terminate_immediately_recipe') }
    runner.should raise_exception(RightScale::Test::ChefRunner::MockSystemExit)
    @logger.error_text.should == ""
  end

  it "should fail converge if failed to schedule shutdown" do
    flexmock(@mock_cook).should_receive(:schedule_shutdown).
                         with(::RightScale::ShutdownManagement::TERMINATE, true).
                         and_raise(::RightScale::ShutdownManagement::InvalidLevel, "mock invalid level exception")
    runner = lambda {
      RightScale::Test::ChefRunner.run_chef(
        RsShutdownProviderSpec::TEST_COOKBOOKS_PATH,
        'test::terminate_immediately_recipe') }
    runner.should raise_exception(::RightScale::ShutdownManagement::InvalidLevel)
    @logger.error_text.should == ""  # chef apparently doesn't log exceptions, it just re-raises them after running handlers
  end

end
