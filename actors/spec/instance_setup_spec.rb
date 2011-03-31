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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.join(File.dirname(__FILE__), '..', 'lib', 'instance_setup')
require File.join(File.dirname(__FILE__), 'audit_proxy_mock')
require File.join(File.dirname(__FILE__), 'instantiation_mock')
require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'results_mock')
require 'right_popen'

# We can't mock the different calls to request properly
# rake spec seems to always return the last match
# We can't provide an implementation as a block because we need to
# yield. So monkey patch to the rescue.
class InstanceSetup

  # shorten volume retry delay for tests
  remove_const :VOLUME_RETRY_SECONDS
  VOLUME_RETRY_SECONDS = 0.1

  # limit test retries
  remove_const :MAX_VOLUME_ATTEMPTS
  MAX_VOLUME_ATTEMPTS = 2

  def self.results_factory=(factory)
    @@factory = factory
  end
  def self.repos=(repos)
    @@repos = repos
  end
  def self.bundle=(bundle)
    @@bundle = bundle
  end
  def self.login_policy=(login_policy)
    @@login_policy = login_policy
  end
  def self.agents=(agents)
    @@agents = agents
  end

  @@planned_volume_mappings_results = []
  def self.planned_volume_mappings_results=(results); @@planned_volume_mappings_results = results; end

  @@attach_volume_results = []
  def self.attach_volume_results=(results); @@attach_volume_results = results; end

  @@detach_volume_results = []
  def self.detach_volume_results=(results); @@detach_volume_results = results; end

  def send_retryable_request(operation, *args)
    # defer response to better simulate asynchronous nature of calls to RightNet.
    EM.defer do
      begin
        case operation
        when "/booter/set_r_s_version" then yield @@factory.success_results
        when "/booter/get_repositories" then yield @@repos
        when "/booter/get_boot_bundle" then yield @@bundle
        when "/booter/get_login_policy" then yield @@login_policy
        when "/mapper/list_agents" then yield @@agents
        when "/storage_valet/get_planned_volume_mappings" then yield @@planned_volume_mappings_results.shift
        when "/storage_valet/attach_volume" then yield @@attach_volume_results.shift
        when "/storage_valet/detach_volume" then yield @@detach_volume_results.shift
        else raise ArgumentError.new("Don't know how to mock #{operation}")
        end
      rescue Exception => e
        strand(e)
      end
    end
  end

  def send_persistent_request(operation, *args)
    # defer response to better simulate asynchronous nature of calls to RightNet.
    EM.defer do
      begin
        case operation
        when "/booter/declare" then yield @@factory.success_results
        else raise ArgumentError.new("Don't know how to mock #{operation}")
        end
      rescue Exception => e
        strand(e)
      end
    end
  end

  def self.assert_all_expectations_met
    @@planned_volume_mappings_results.empty?.should == true
    @@attach_volume_results.empty?.should == true
    @@detach_volume_results.empty?.should == true
  end

  def self.reset_expectations
    @@planned_volume_mappings_results = []
    @@attach_volume_results = []
    @@detach_volume_results = []
  end
end

module RightScale
  class InstanceSetupSpec

    KILOBYTE = 1024
    MEGABYTE = KILOBYTE * 1024
    GIGABYTE = MEGABYTE * 1024

    class MockVolumeManager
      def initialize
        @disks_results = []
        @volumes_results = []
        @partitions_results = []
        @format_disk_results = []
        @online_disk_results = []
        @assign_device_results = []
      end

      def is_attachable_volume_path?(path); true; end

      def disks(conditions = nil); return @disks_results.shift; end
      def disks_results=(results); @disks_results = results; end

      def volumes(conditions = nil); return @volumes_results.shift; end
      def volumes_results=(results); @volumes_results = results; end

      def partitions(disk_index, conditions = nil); @partitions_results.shift.call(disk_index); end
      def partitions_results=(results); @partitions_results = results; end

      def format_disk(disk_index, device); @format_disk_results.shift.call(disk_index); end
      def format_disk_results=(results); @format_disk_results = results; end

      def online_disk(disk_index); @online_disk_results.shift.call(disk_index); end
      def online_disk_results=(results); @online_disk_results = results; end

      def assign_device(volume_index, device); @assign_device_results.shift.call(volume_index, device); end
      def assign_device_results=(results); @assign_device_results = results; end

      def assert_all_expectations_met
        @disks_results.empty?.should == true
        @volumes_results.empty?.should == true
        @partitions_results.empty?.should == true
        @format_disk_results.empty?.should == true
        @online_disk_results.empty?.should == true
        @assign_device_results.empty?.should == true
      end
    end
  end
end

describe InstanceSetup do

  include RightScale::SpecHelpers

  before(:each) do
    @agent_identity = RightScale::AgentIdentity.new('rs', 'test', 1)
    @setup = flexmock(InstanceSetup.allocate)
    @setup.should_receive(:configure_repositories).and_return(RightScale::OperationResult.success)
    tags_manager_mock = flexmock(RightScale::AgentTagsManager)
    tags_manager_mock.should_receive(:tags).and_yield []
    flexmock(RightScale::AgentTagsManager).should_receive(:instance).and_return(tags_manager_mock)
    @audit = RightScale::AuditProxyMock.new(1)
    flexmock(RightScale::AuditProxy).should_receive(:new).and_return(@audit)
    @results_factory = RightScale::ResultsMock.new
    InstanceSetup.results_factory = @results_factory
    @mgr = RightScale::LoginManager.instance
    flexmock(@mgr).should_receive(:supported_by_platform?).and_return(true)
    flexmock(@mgr).should_receive(:write_keys_file).and_return(true)
    status = flexmock('status', :success? => true)
    flexmock(RightScale).should_receive(:popen3).and_return { |o| o[:target].send(o[:exit_handler], status) }
    setup_state
    @mapper_proxy.should_receive(:initialize_offline_queue).and_yield

    # stub out planned volumes for windows, cause failure under Mac/Linux where call is unexpected.
    planned_volume_mapping_result = if RightScale::Platform.windows?; @results_factory.success_results([]); else; @results_factory.error_results("Unexpected call for platform."); end
    InstanceSetup.planned_volume_mappings_results = [planned_volume_mapping_result]

    # prevent Chef logging reaching the console during spec test.
    logger = flexmock(::RightScale::RightLinkLog.logger)
    logger.should_receive(:info).and_return(true)
    logger.should_receive(:error).and_return(true)  # FIX: it would be useful to collect logged errors for display on failure
  end

  after(:each) do
    cleanup_state
    cleanup_script_execution
    InstanceSetup.reset_expectations
  end

  # Stop EM if setup reports a state of 'running' or 'stranded'
  def check_state
    EM.stop if @setup.report_state.content =~ /operational|stranded/
  end
 
  def boot(login_policy, repos, bundle = nil)
    login_policy = @results_factory.success_results(login_policy)
    repos        = @results_factory.success_results(repos)

    if bundle
      bundle = @results_factory.success_results(bundle)
    else
      bundle = @results_factory.error_results('Test')
    end

    InstanceSetup.login_policy = login_policy
    InstanceSetup.repos = repos
    InstanceSetup.bundle = bundle

    result = RightScale::OperationResult.success({ 'agent_id1' => { 'tags' => ['tag1'] } })
    agents = flexmock('result', :results => { 'mapper_id1' => result })
    InstanceSetup.agents = agents

    EM.run do
      @setup.__send__(:initialize, @agent_identity.to_s)
      EM.add_periodic_timer(0.1) { check_state }
      EM.add_timer(25) { EM.stop }
    end
  end

  def kilobytes(value)
    return value * RightScale::InstanceSetupSpec::KILOBYTE
  end

  def megabytes(value)
    return value * RightScale::InstanceSetupSpec::MEGABYTE
  end

  def gigabytes(value)
    return value * RightScale::InstanceSetupSpec::GIGABYTE
  end

  def handle_partitions(actual_index, expected_index, result)
    actual_index.should == expected_index
    result
  end

  def handle_format_disk(disk_index, device, disk, volume)
    disk_index.should == disk[:index]
    disk.merge!(:status => 'Online', :free_size => 0)
    volume.merge!(:device => device, :filesystem => 'NTFS')
    true
  end

  def handle_online_disk(disk_index, device, disk, volume)
    handle_format_disk(disk_index, device, disk, volume)

    # online_disk may or may not set the next available device name (2003 yes,
    # 2008+ maybe (exact criteria is unclear).
    srand
    volume[:device] = nil if 0 == rand(2)
    true
  end

  def handle_assign_device(volume_index, device, expected_device, volume)
    volume_index.should == volume[:index]
    device.should == expected_device
    volume.merge!(:device => device)
    true
  end

  def boot_test
    policy = RightScale::InstantiationMock.login_policy
    repos  = RightScale::InstantiationMock.repositories
    bundle = RightScale::InstantiationMock.script_bundle('__TestScripts', '__TestScripts_too')
    boot(policy, repos, bundle)
    res = @setup.report_state
    if !res.success? || res.content != 'operational'
      # FIX: also print errors from mock logger for debugging purposes since audits are abbreviated
      puts "*** Audits from unexpected stranding ***"
      @audit.audits.each { |a| puts a[:text] }
      puts "****************************************"
    end
    res.should be_success
    res.content.should == 'operational'
  end

  def mock_core_api_planned_volume_mappings
    mappings = []
    mappings << {:volume_id => 'test_vol_D', :device => 'D:',  # map blank volume to D:
                 :volume_status => 'attached'}
    mappings << {:volume_id => 'test_vol_F', :device => 'F:',  # snapshot volume might online automatically as E: but we explicitly request F:
                 :volume_status => 'attached'}
    results = []
    results << [mappings[0], mappings[1]]   # all volumes are initially attached in first implementation of core api
    results << []                           # detach-all removes all instance associations with volumes
    results << [mappings[0]]                # after attaching first volume
    results << [mappings[0]]                # before attaching second volume
    results << [mappings[0], mappings[1]]   # after attaching second volume
    results << [mappings[0], mappings[1]]   # final evaluation before proceeding to boot
    InstanceSetup.planned_volume_mappings_results = results.map { |result| @results_factory.success_results(result) }
    mappings
  end

  def mock_core_api_detach_volume(mappings)
    results = []
    results << @results_factory.success_results({:volume_id => mappings[0][:volume_id]})
    results << @results_factory.success_results({:volume_id => mappings[1][:volume_id]})
    InstanceSetup.detach_volume_results = results
  end

  def mock_core_api_attach_volume
    results = []
    2.times { results << @results_factory.success_results({}) }
    InstanceSetup.attach_volume_results = results
  end

  def mock_vm_disks
    mock_vm = RightScale::RightLinkConfig[:platform].volume_manager
    disks = []
    disks << {:index => 0, :status => 'Online', :total_size => gigabytes(30),  # disk0 is the boot volume.
              :free_size => kilobytes(8033), :dynamic => false, :gpt => false}
    disks << {:index => 1, :status => 'Offline', :total_size => gigabytes(32), # disk1 is a blank (unformatted volume).
              :free_size => gigabytes(32), :dynamic => false, :gpt => false }
    disks << {:index => 2, :status => 'Offline', :total_size => gigabytes(2),  # disk2 is a snapshot volume with existing content.
              :free_size => 0, :dynamic => false, :gpt => false }
    results = []
    results << [disks[0]]                     # after detach-all only boot volume remains, before first attach
    results << [disks[0], disks[1]]           # after first attachment
    results << [disks[0], disks[1]]           # before second attachment
    results << [disks[0], disks[1], disks[2]] # after second attachment
    mock_vm.disks_results = results
    disks
  end

  def mock_vm_volumes
    mock_vm = RightScale::RightLinkConfig[:platform].volume_manager
    volumes = []
    volumes << {:index => 0, :device => "C:", :label => '2008Boot',    # boot volume C:
                :filesystem => 'NTFS', :type => 'Partition',
                :total_size => gigabytes(80), :status => 'Healthy', :info => 'System'}
    volumes << {:index => 1, :device => nil, :label => nil,            # blank volume planned for D:
                :filesystem => nil, :type => 'Partition',
                :total_size => gigabytes(32), :status => 'Healthy', :info => nil}
    volumes << {:index => 2, :device => nil, :label => 'OEM_2008x64',  # snapshot volume planned for E:
                :filesystem => 'NTFS', :type => 'Partition',
                :total_size => gigabytes(2), :status => 'Healthy', :info => nil}
    results = []
    results << [volumes[0]]                         # after detach-all only boot volume remains, before first attach
    results << [volumes[0], volumes[1]]             # after first attachment
    results << [volumes[0], volumes[1]]             # before second attachment
    results << [volumes[0], volumes[1]]             # after second attachment
    results << [volumes[0], volumes[1], volumes[2]] # after online disk
    mock_vm.volumes_results = results
    volumes
  end

  def mock_vm_partitions(disks)
    mock_vm = RightScale::RightLinkConfig[:platform].volume_manager
    partitions = []
    partitions << nil  # algorithm doesn't care about disk 0 (boot volume) partitions
    partitions << []   # disk 1 blank volume has no partitions initially
    partitions << [{:index => 1, :type => 'Primary', :size => gigabytes(2), :offset => kilobytes(32)}]  # snapshot disk has one partition
    results = []
    results << lambda { |disk_index| handle_partitions(disk_index, disks[1][:index], partitions[1]) }
    results << lambda { |disk_index| handle_partitions(disk_index, disks[2][:index], partitions[2]) }
    mock_vm.partitions_results = results
    partitions
  end

  def mock_vm_format_disk(mappings, disks, volumes)
    mock_vm = RightScale::RightLinkConfig[:platform].volume_manager
    results = []
    results << lambda { |disk_index| handle_format_disk(disk_index, mappings[0][:device], disks[1], volumes[1]) }
    mock_vm.format_disk_results = results
  end

  def mock_vm_online_disk(disks, volumes)
    mock_vm = RightScale::RightLinkConfig[:platform].volume_manager
    results = []
    results << lambda { |disk_index| handle_online_disk(disk_index, "P:", disks[2], volumes[2]) }
    mock_vm.online_disk_results = results
  end

  def mock_vm_assign_device(mappings, volumes)
    mock_vm = RightScale::RightLinkConfig[:platform].volume_manager
    results = []
    results << lambda { |volume_index, device| handle_assign_device(volume_index, device, mappings[1][:device], volumes[2]) }
    mock_vm.assign_device_results = results
  end

  if RightScale::Platform.windows?
    it 'should boot after managing planned volumes' do

      # setup series of responses to mock both core agent api and windows volume management.
      flexmock(RightScale::RightLinkConfig[:platform]).should_receive(:volume_manager).and_return(RightScale::InstanceSetupSpec::MockVolumeManager.new)
      mappings = mock_core_api_planned_volume_mappings
      mock_core_api_detach_volume(mappings)
      mock_core_api_attach_volume
      disks = mock_vm_disks
      volumes = mock_vm_volumes
      mock_vm_partitions(disks)
      mock_vm_format_disk(mappings, disks, volumes)
      mock_vm_online_disk(disks, volumes)
      mock_vm_assign_device(mappings, volumes)

      # test.
      boot_test

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      RightScale::RightLinkConfig[:platform].volume_manager.assert_all_expectations_met

    end
  else

    it 'should boot' do
      boot_test
    end

  end

  it 'should strand' do
    boot(RightScale::InstantiationMock.login_policy, RightScale::InstantiationMock.repositories)
    res = @setup.report_state
    res.should be_success
    res.content.should == 'stranded'
  end

end
