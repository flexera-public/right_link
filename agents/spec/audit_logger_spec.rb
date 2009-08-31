require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'audit_logger'

describe RightScale::AuditLogger do

  before(:each) do
    @auditor = mock('Auditor')
    @logger = RightScale::AuditLogger.new(@auditor)
    @logger.level = Logger::DEBUG
  end

  it 'should append raw audits' do
    @auditor.should_receive(:append_raw_output).with('fourty two')
    @logger << 'fourty two'
  end

  it 'should append info and debug text' do
    @auditor.should_receive(:append_info).exactly(4).times
    @auditor.should_not_receive(:append_error)
    @logger.debug
    @logger.info
    @logger.warn
    @logger.unknown
  end

  it 'should append error text' do
    @auditor.should_not_receive(:append_info)
    @auditor.should_receive(:append_error).twice
    @logger.error
    @logger.fatal
  end

end
