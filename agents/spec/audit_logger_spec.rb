require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'common', 'right_link_log')
require 'audit_logger'

describe RightScale::AuditLogger do

  before(:each) do
    @auditor = flexmock('Auditor')
    @logger = RightScale::AuditLogger.new(@auditor)
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
