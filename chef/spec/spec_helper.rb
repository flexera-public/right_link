#
# Copyright (c) 2009 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'instance'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'instance', 'cook'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'providers'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'cloud_utilities.rb'))

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

shared_examples_for 'mocks state' do
  include RightScale::SpecHelpers

  before(:each) do
    setup_state
  end

  after(:each) do
    cleanup_state
  end
end
