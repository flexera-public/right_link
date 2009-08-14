require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'audit_formatter'
require 'right_link_log'
require 'auditor_proxy'

describe RightScale::AuditorProxy do

  before(:each) do
    @proxy = RightScale::AuditorProxy.new(1)
    @instance = mock('instance')
    Nanite::MapperProxy.should_receive(:instance).and_return(@instance)
  end

  it 'should log and audit errors' do
    RightScale::RightLinkLog.logger.should_receive(:error).once.with("AUDIT *ERROR> ERROR")
    @instance.should_receive(:request).once
    @proxy.append_error('ERROR')
  end

  it 'should log statuses' do
    RightScale::RightLinkLog.logger.should_receive(:info).once.with("AUDIT *RS> STATUS")
    @instance.should_receive(:request).once
    @proxy.update_status('STATUS')
  end

it 'should log outputs' do
    RightScale::RightLinkLog.logger.should_receive(:info).once.with("AUDIT OUTPUT")
    @instance.should_receive(:request).once
    @proxy.append_output('OUTPUT')
  end
  
  it 'should log raw outputs' do
    RightScale::RightLinkLog.logger.should_receive(:info).once.with('AUDIT RAW OUTPUT')
    @instance.should_receive(:request).once
    @proxy.append_raw_output('RAW OUTPUT')
  end

  it 'should log sections' do
    RightScale::RightLinkLog.logger.should_receive(:info).once.with("AUDIT #{ '****' * 20 }\n*RS>#{ 'SECTION'.center(72) }****")
    @instance.should_receive(:request).once
    @proxy.create_new_section('SECTION')
  end

  it 'should log information' do
    RightScale::RightLinkLog.logger.should_receive(:info).once.with("AUDIT *RS> INFO")
    @instance.should_receive(:request).once
    @proxy.append_info('INFO')
  end

end
