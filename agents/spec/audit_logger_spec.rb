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
#
require File.join(File.dirname(__FILE__), 'spec_helper')
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common', 'right_link_log'))

describe RightScale::AuditLogger do

  before(:each) do
    @auditor = flexmock(RightScale::AuditorProxy.instance)
    @logger = RightScale::AuditLogger.new(1)
    @logger.level = Logger::DEBUG
  end

  it 'should append info text' do
    @auditor.should_receive(:append_output).times(3)
    @logger.info
    @logger.warn
    @logger.unknown
  end

  it 'should log debug text' do
    flexmock(RightScale::RightLinkLog).should_receive(:debug).once
    @logger.debug
  end

  it 'should append error text' do
    @auditor.should_receive(:append_error).twice
    @logger.error
    @logger.fatal
  end

end
