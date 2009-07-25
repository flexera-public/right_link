require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')
require 'audit_formatter'
require 'auditor_proxy'

describe RightScale::AuditorProxy do

  before(:each) do
    @proxy = RightScale::AuditorProxy.new(1)
    @instance = mock('instance')
    Nanite::MapperProxy.should_receive(:instance).and_return(@instance)
  end

  it 'should log and audit errors' do
    Nanite::Log.logger.should_receive(:error).once.with("*ERROR> ERROR\n")
    @instance.should_receive(:request).once
    @proxy.append_error('ERROR')
  end

  it 'should log statuses' do
    Nanite::Log.logger.should_receive(:info).once.with("*RS> STATUS\n")
    @instance.should_receive(:request).once
    @proxy.update_status('STATUS')
  end

it 'should log outputs' do
    Nanite::Log.logger.should_receive(:info).once.with("OUTPUT\n")
    @instance.should_receive(:request).once
    @proxy.append_output('OUTPUT')
  end
  
  it 'should log raw outputs' do
    Nanite::Log.logger.should_receive(:info).once.with('RAW OUTPUT')
    @instance.should_receive(:request).once
    @proxy.append_raw_output('RAW OUTPUT')
  end

  it 'should log sections' do
    Nanite::Log.logger.should_receive(:info).once.with("#{ '****' * 20 }\n*RS>#{ 'SECTION'.center(72) }****\n")
    @instance.should_receive(:request).once
    @proxy.create_new_section('SECTION')
  end

  it 'should log information' do
    Nanite::Log.logger.should_receive(:info).once.with("*RS> INFO\n")
    @instance.should_receive(:request).once
    @proxy.append_info('INFO')
  end

end
