#
# Copyright (c) 2009-2011 RightScale Inc
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

require File.expand_path('../../spec_helper', __FILE__)
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'instance', 'cook'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'clouds'))

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'chef', 'right_providers'))

shared_examples_for 'generates cookbook for chef runner' do
  before(:all) do
    create_cookbook
  end

  after(:all) do
    cleanup
  end
end

shared_examples_for 'mocks logging' do
  require File.normalize_path(File.join(File.dirname(__FILE__), 'mock_auditor_proxy'))
  include RightScale::Test::MockAuditorProxy

  # Asserts that the given text appears somewhere in the log for the given level.
  #
  # === Parameters
  # level(String|Token):: logger level to find
  # str_to_match(String):: literal text to find
  #
  # === Returns
  # result(true|false):: true if found text
  def log_should_contain_text(level, str_to_match, invert_should=false)
    # remove newlines and spaces to handle any line-wrapping weirdness (in Windows), etc.
    expected_message = Regexp.escape(str_to_match.gsub(/\s+/, ''))

    # un-escape the escaped regex strings
    expected_message.gsub!("\\.\\*", ".*")

    # should contain the expected exception
    kind = (level.to_s + '_text').to_sym
    logged_output = @logger.send(kind)
    actual_message = logged_output.gsub(/\s+/, '')
    if invert_should
      actual_message.should_not match(expected_message)
    else
      actual_message.should match(expected_message)
    end
  end

  # Asserts that the given text does not appear somewhere in the log for the given level.
  #
  # === Parameters
  # level(String|Token):: logger level to find
  # str_to_match(String):: literal text to find
  #
  # === Returns
  # result(true|false):: true if found text
  def log_should_not_contain_text(level, str_to_match)
    log_should_contain_text(level, str_to_match, invert_should=true)
  end

  # Asserts the given logger level has no logged messages.
  #
  # === Parameters
  # level(String|Token):: logger level to find
  #
  # === Returns
  # result(true|false):: true if found any logged messages
  def log_should_be_empty(level)
    kind = (level.to_s + '_text').to_sym
    @logger.send(kind).strip.should == ''
  end

  before(:each) do
    @logger = RightScale::Test::MockLogger.new
    mock_chef_log(@logger)
    mock_right_link_log(@logger)

    @auditor = flexmock(RightScale::AuditStub.instance)
    @auditor.should_receive(:create_new_section).and_return { |m| @logger.audit_section << m }
    @auditor.should_receive(:append_info).and_return { |m| @logger.audit_info << m }
    @auditor.should_receive(:append_output).and_return { |m| @logger.audit_output << m }
    @auditor.should_receive(:update_status).and_return { |m| @logger.audit_status << m }
  end
end
