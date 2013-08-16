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
#
require File.join(File.dirname(__FILE__), 'spec_helper')
require 'right_agent/log'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook', 'audit_stub'))

describe RightScale::AuditLogger do
  LOG_FIXTURES = {}

  # Load some fixtures from disk, that comprise some log file excerpts captured from actual RightLink instances.
  # The fixtures are stored in memory as a hash, where the key is the OS on which the log output
  # was captured ('windows' or 'linux') and the values are an ordered sequence of individual log entries,
  # each which may consist of multiple lines.
  fixtures_dir = File.expand_path('../fixtures/error_logs', __FILE__)
  ['linux', 'windows'].each do |os|
    LOG_FIXTURES[os] = []
    Dir.glob(File.join(fixtures_dir, "right_script_failure.#{os}.*.txt")).sort.each do |file|
      LOG_FIXTURES[os] << File.read(file)
    end
  end

  before(:each) do
    @auditor = flexmock(RightScale::AuditStub.instance)
    @logger = RightScale::AuditLogger.new
    @logger.level = Logger::DEBUG
  end

  it 'should append info text' do
    @auditor.should_receive(:append_output).times(3)
    @logger.info
    @logger.warn
    @logger.unknown
  end

  it 'should log debug text' do
    flexmock(RightScale::Log).should_receive(:debug)
    @auditor.should_receive(:append_output)
    @logger.debug
  end

  it 'should append error text' do
    @auditor.should_receive(:append_error).twice
    @logger.error
    @logger.fatal
  end

  # Dynamically generate some test cases for log filtering based on the fixtures we have
  LOG_FIXTURES.each_pair do |os, log_entries|
    context "under #{os}" do
      it "should filter RightScript errors from audit output" do
        pending('missing fixtures') if log_entries.empty?
        @auditor.should_receive(:append_error).twice
        log_entries.each { |line|
          @logger.error(line)
        }
      end
    end
  end

end
