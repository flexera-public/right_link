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

module RightScale
  class VolumeManagement

    # shorten volume retry delay for tests
    remove_const :VOLUME_RETRY_SECONDS
    VOLUME_RETRY_SECONDS = 0.1

    # limit test retries
    remove_const :MAX_VOLUME_ATTEMPTS
    MAX_VOLUME_ATTEMPTS = 2

  end
end

# We can't mock the different calls to request properly
# rake spec seems to always return the last match
# We can't provide an implementation as a block because we need to
# yield. So monkey patch to the rescue.
class InstanceSetup

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

  @@results_for_get_planned_volumes = []
  def self.results_for_get_planned_volumes; @@results_for_get_planned_volumes; end
  def self.results_for_get_planned_volumes=(results); @@results_for_get_planned_volumes = results; end

  @@results_for_attach_volume = []
  def self.results_for_attach_volume; @@results_for_attach_volume; end
  def self.results_for_attach_volume=(results); @@results_for_attach_volume = results; end

  @@results_for_detach_volume = []
  def self.results_for_detach_volume; @@results_for_detach_volume; end
  def self.results_for_detach_volume=(results); @@results_for_detach_volume = results; end

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
        when "/storage_valet/get_planned_volumes" then yield @@results_for_get_planned_volumes.shift.call(*args)
        when "/storage_valet/attach_volume" then yield @@results_for_attach_volume.shift.call(*args)
        when "/storage_valet/detach_volume" then yield @@results_for_detach_volume.shift.call(*args)
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
    @@results_for_get_planned_volumes.size.should == 0
    @@results_for_attach_volume.size.should == 0
    @@results_for_detach_volume.size.should == 0
  end

  def self.reset_expectations
    @@results_for_get_planned_volumes = []
    @@results_for_attach_volume = []
    @@results_for_detach_volume = []
  end
end

module RightScale
  class InstanceSetupSpec

    KILOBYTE = 1024
    MEGABYTE = KILOBYTE * 1024
    GIGABYTE = MEGABYTE * 1024

    class MockVolumeManager
      def initialize
        @results_for_disks = []
        @results_for_volumes = []
        @results_for_partitions = []
        @results_for_format_disk = []
        @results_for_online_disk = []
        @results_for_assign_device = []
      end

      def is_attachable_volume_path?(path); true; end

      def disks(conditions = nil); return @results_for_disks.shift.call; end
      def results_for_disks; @results_for_disks; end
      def results_for_disks=(results); @results_for_disks = results; end

      def volumes(conditions = nil); return @results_for_volumes.shift.call; end
      def results_for_volumes; @results_for_volumes; end
      def results_for_volumes=(results); @results_for_volumes = results; end

      def partitions(disk_index, conditions = nil); @results_for_partitions.shift.call(disk_index); end
      def results_for_partitions; @results_for_partitions; end
      def results_for_partitions=(results); @results_for_partitions = results; end

      def format_disk(disk_index, device); @results_for_format_disk.shift.call(disk_index); end
      def results_for_format_disk; @results_for_format_disk; end
      def results_for_format_disk=(results); @results_for_format_disk = results; end

      def online_disk(disk_index); @results_for_online_disk.shift.call(disk_index); end
      def results_for_online_disk; @results_for_online_disk; end
      def results_for_online_disk=(results); @results_for_online_disk = results; end

      def assign_device(volume_index, device); @results_for_assign_device.shift.call(volume_index, device); end
      def results_for_assign_device; @results_for_assign_device; end
      def results_for_assign_device=(results); @results_for_assign_device = results; end

      def assert_all_expectations_met
        @results_for_disks.size.should == 0
        @results_for_volumes.size.should == 0
        @results_for_partitions.size.should == 0
        @results_for_format_disk.size.should == 0
        @results_for_online_disk.size.should == 0
        @results_for_assign_device.size.should == 0
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

    # always mock volume manager in testing (it can be hazardous to your dev/test machine's health).
    @mock_vm = RightScale::InstanceSetupSpec::MockVolumeManager.new
    flexmock(RightScale::RightLinkConfig[:platform]).should_receive(:volume_manager).and_return(@mock_vm)

    # default to no planned volumes in Windows case, Linux case will fail if it attempts to get planned volumes.
    if RightScale::RightLinkConfig[:platform].windows?
      InstanceSetup.results_for_get_planned_volumes = [lambda{ @results_factory.success_results([]) }]
    else
      InstanceSetup.results_for_get_planned_volumes = [lambda{ raise "Unexpected call for this platform." }]
    end

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

  def handle_get_planned_volume_mappings(payload, expected_agent_id, result)
    payload.should == {:agent_identity => expected_agent_id}
    return @results_factory.success_results(result)
  end

  def handle_attach_volume(payload, expected_agent_id, planned_volume)
    payload.should == {:agent_identity => expected_agent_id, :volume_id => planned_volume.volume_id, :device_name => planned_volume.device_name}
    return @results_factory.success_results({})
  end

  def handle_detach_volume(payload, expected_agent_id, planned_volume)
    payload.should == {:agent_identity => expected_agent_id, :device_name => planned_volume.device_name}
    return @results_factory.success_results({:volume_id => planned_volume.volume_id})
  end

  def handle_partitions(actual_index, expected_index, result)
    actual_index.should == expected_index
    result
  end

  def handle_format_disk(disk_index, mount_point, disk, volume)
    disk_index.should == disk[:index]
    disk.merge!(:status => 'Online', :free_size => 0)
    volume.merge!(:device => mount_point, :filesystem => 'NTFS')
    true
  end

  def handle_online_disk(disk_index, mount_point, disk, volume)
    handle_format_disk(disk_index, mount_point, disk, volume)

    # online_disk may or may not set the next available device name (2003 yes,
    # 2008+ maybe (exact criteria is unclear).
    srand
    volume[:device] = nil if 0 == rand(2)
    true
  end

  def handle_assign_device(volume_device_or_index, device, expected_device, volume)
    expected_volume_device_or_index = volume[:device] || volume[:index]
    volume_device_or_index.should == expected_volume_device_or_index
    device.should == expected_device
    volume.merge!(:device => device)
    true
  end

  def boot_to_operational
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

  def boot_to_stranded_with(expected_audit)
    boot(RightScale::InstantiationMock.login_policy, RightScale::InstantiationMock.repositories)
    res = @setup.report_state
    res.should be_success
    res.content.should == 'stranded'
    @audit.audits.last[:text].should == expected_audit
  end

  def mock_core_api_get_planned_volumes
    planned_volumes = []
    planned_volumes << RightScale::PlannedVolume.new('test_vol_D', 'xvdd', ['D:'], 'attached')  # map blank volume to D:
    planned_volumes << RightScale::PlannedVolume.new('test_vol_F', 'xvdf', ['F:'], 'attached')  # snapshot volume might online automatically as E: but we explicitly request F:
    results = []
    results << [planned_volumes[0], planned_volumes[1]]   # all volumes are initially attached in first implementation of core api
    results << []                                         # detach-all removes all instance associations with volumes
    results << [planned_volumes[0]]                       # after attaching first volume
    results << [planned_volumes[0]]                       # before attaching second volume
    results << [planned_volumes[0], planned_volumes[1]]   # after attaching second volume
    results << [planned_volumes[0], planned_volumes[1]]   # final evaluation before proceeding to boot
    InstanceSetup.results_for_get_planned_volumes = results.map { |result| lambda{ |payload| handle_get_planned_volume_mappings(payload, @agent_identity.to_s, result) } }
    planned_volumes
  end

  def mock_core_api_attach_volume(planned_volumes)
    results = []
    planned_volumes.each do |planned_volume|
      results << lambda{ |payload| handle_attach_volume(payload, @agent_identity.to_s, planned_volume) }
    end
    InstanceSetup.results_for_attach_volume = results
  end

  def mock_core_api_detach_volume(planned_volumes)
    results = []
    planned_volumes.each do |planned_volume|
      results << lambda{ |payload| handle_detach_volume(payload, @agent_identity.to_s, planned_volume) }
    end
    InstanceSetup.results_for_detach_volume = results
  end

  def mock_vm_disks
    disks = []
    disks << {:index => 0, :status => 'Online', :total_size => gigabytes(30),  # disk0 is the boot volume.
              :free_size => kilobytes(8033), :dynamic => false, :gpt => false}
    disks << {:index => 1, :status => 'Offline', :total_size => gigabytes(32), # disk1 is a blank (unformatted volume).
              :free_size => gigabytes(32), :dynamic => false, :gpt => false }
    disks << {:index => 2, :status => 'Offline', :total_size => gigabytes(2),  # disk2 is a snapshot volume with existing content.
              :free_size => 0, :dynamic => false, :gpt => false }
    results = []
    results << lambda {[disks[0]]}                      # after detach-all only boot volume remains, before first attach
    results << lambda {[disks[0], disks[1]]}            # after first attachment
    results << lambda {[disks[0], disks[1]]}            # before second attachment
    results << lambda {[disks[0], disks[1], disks[2]]}  # after second attachment
    @mock_vm.results_for_disks = results
    disks
  end

  def mock_vm_volumes
    volumes = []
    volumes << {:index => 0, :device => "C:", :label => '2008Boot',   # boot volume C:
                :filesystem => 'NTFS', :type => 'Partition',
                :total_size => gigabytes(80), :status => 'Healthy', :info => 'System'}
    volumes << {:index => 1, :device => nil, :label => nil,           # blank volume planned for D:
                :filesystem => nil, :type => 'Partition',
                :total_size => gigabytes(32), :status => 'Healthy', :info => nil}
    volumes << {:index => 2, :device => nil, :label => '2008Media',   # snapshot volume planned for F:
                :filesystem => 'NTFS', :type => 'Partition',
                :total_size => gigabytes(2), :status => 'Healthy', :info => nil}
    results = []
    results << lambda {[volumes[0]]}                          # after detach-all only boot volume remains, before first attach
    results << lambda {[volumes[0], volumes[1]]}              # after first attachment
    results << lambda {[volumes[0], volumes[1]]}              # before second attachment
    results << lambda {[volumes[0], volumes[1]]}              # after second attachment
    results << lambda {[volumes[0], volumes[1], volumes[2]]}  # after online disk
    @mock_vm.results_for_volumes = results
    volumes
  end

  def mock_vm_partitions(disks)
    partitions = []
    partitions << nil  # algorithm doesn't care about disk 0 (boot volume) partitions
    partitions << []   # disk 1 blank volume has no partitions initially
    partitions << [{:index => 1, :type => 'Primary', :size => gigabytes(2), :offset => kilobytes(32)}]  # snapshot disk has one partition
    results = []
    results << lambda { |disk_index| handle_partitions(disk_index, disks[1][:index], partitions[1]) }
    results << lambda { |disk_index| handle_partitions(disk_index, disks[2][:index], partitions[2]) }
    @mock_vm.results_for_partitions = results
    partitions
  end

  def mock_vm_format_disk(planned_volumes, disks, volumes)
    results = []
    results << lambda { |disk_index| handle_format_disk(disk_index, planned_volumes[0].mount_points.first, disks[1], volumes[1]) }
    @mock_vm.results_for_format_disk = results
  end

  def mock_vm_online_disk(disks, volumes)
    results = []
    results << lambda { |disk_index| handle_online_disk(disk_index, "P:", disks[2], volumes[2]) }
    @mock_vm.results_for_online_disk = results
  end

  def mock_vm_assign_device(planned_volumes, volumes)
    results = []
    results << lambda { |volume_device_or_index, device| handle_assign_device(volume_device_or_index, device, planned_volumes[1].mount_points.first, volumes[2]) }
    @mock_vm.results_for_assign_device = results
  end

  if RightScale::Platform.windows?
    it 'should boot after managing planned volumes' do
      # setup series of responses to mock both core agent api and windows volume management.
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      mock_core_api_attach_volume(planned_volumes)
      disks = mock_vm_disks
      volumes = mock_vm_volumes
      mock_vm_partitions(disks)
      mock_vm_format_disk(planned_volumes, disks, volumes)
      mock_vm_online_disk(disks, volumes)
      mock_vm_assign_device(planned_volumes, volumes)

      # test.
      boot_to_operational

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when get planned volume mappings fails' do
      # cause failure to get.
      results = []
      results << lambda{ @results_factory.error_results("Simluating unknown call failure.") }
      InstanceSetup.results_for_get_planned_volumes = results

      # test.
      boot_to_stranded_with "Failed to retrieve planned volume mappings: Simluating unknown call failure."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
    end

    it 'should strand when detach planned volumes fails' do
      # standard mocks.
      planned_volumes = mock_core_api_get_planned_volumes

      # tweak mocks to repeat the first planned volume mappings response.
      results = []
      # expect requery of current volume status once per detach pass.
      RightScale::VolumeManagement::MAX_VOLUME_ATTEMPTS.times { results << InstanceSetup.results_for_get_planned_volumes[0] }
      InstanceSetup.results_for_get_planned_volumes = results
      results = []
      total_detach_retries = 1 + planned_volumes.size * (RightScale::VolumeManagement::MAX_VOLUME_ATTEMPTS - 1)  # max-1 attempts to detach all then once more to strand
      total_detach_retries.times { results << lambda{ @results_factory.error_results("Simulating failure to detach volume.") } }
      InstanceSetup.results_for_detach_volume = results

      # test.
      boot_to_stranded_with "Exceeded maximum of #{RightScale::VolumeManagement::MAX_VOLUME_ATTEMPTS} attempts detaching "\
                            "volume #{planned_volumes[0].volume_id} with error: Simulating failure to detach volume."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
    end

    it 'should strand when attach planned volumes fails' do
      # standard mocks.
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      @mock_vm.results_for_disks = [lambda{[]}]     # ignored
      @mock_vm.results_for_volumes = [lambda{[]}]   # ignored

      # tweak mocks to repeat the second planned volume mappings response.
      results = []
      results << InstanceSetup.results_for_get_planned_volumes[0]
      # expect requery of current volume status once per attach pass.
      RightScale::VolumeManagement::MAX_VOLUME_ATTEMPTS.times { results << InstanceSetup.results_for_get_planned_volumes[1] }
      InstanceSetup.results_for_get_planned_volumes = results
      results = []
      RightScale::VolumeManagement::MAX_VOLUME_ATTEMPTS.times { results << lambda { @results_factory.error_results("Simulating failure to attach volume.") } }
      InstanceSetup.results_for_attach_volume = results

      # test.
      boot_to_stranded_with "Exceeded maximum of #{RightScale::VolumeManagement::MAX_VOLUME_ATTEMPTS} attempts attaching "\
                            "volume #{planned_volumes[0].volume_id} with error: Simulating failure to attach volume."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when list disks fails' do
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      @mock_vm.results_for_disks = [lambda{ raise "Simulating vm disks error." }]

      # tweak mocks to only give the first two planned volume mappings responses.
      InstanceSetup.results_for_get_planned_volumes = InstanceSetup.results_for_get_planned_volumes[0, 2]

      # test.
      boot_to_stranded_with "Simulating vm disks error."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when list volumes fails' do
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      @mock_vm.results_for_disks = [lambda{[]}]     # ignored
      @mock_vm.results_for_volumes = [lambda{ raise "Simulating vm volumes error." }]

      # tweak mocks to only give the first two planned volume mappings responses.
      InstanceSetup.results_for_get_planned_volumes = InstanceSetup.results_for_get_planned_volumes[0, 2]

      # test.
      boot_to_stranded_with "Simulating vm volumes error."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when list partitions fails' do
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      mock_core_api_attach_volume(planned_volumes)
      mock_vm_disks
      mock_vm_volumes
      @mock_vm.results_for_partitions = [lambda{ raise "Simulating vm partitions error." }]

      # tweak mocks to only give the results leading to first call to partitions.
      InstanceSetup.results_for_get_planned_volumes = InstanceSetup.results_for_get_planned_volumes[0, 3]
      InstanceSetup.results_for_attach_volume = InstanceSetup.results_for_attach_volume[0, 1]
      @mock_vm.results_for_disks = @mock_vm.results_for_disks[0, 2]
      @mock_vm.results_for_volumes = @mock_vm.results_for_volumes[0, 2]

      # test.
      boot_to_stranded_with "Simulating vm partitions error."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when format disk fails' do
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      mock_core_api_attach_volume(planned_volumes)
      disks = mock_vm_disks
      mock_vm_volumes
      mock_vm_partitions(disks)
      @mock_vm.results_for_format_disk = [lambda{ raise "Simulating vm format disk error." }]

      # tweak mocks to only give the results leading to call to format disk.
      InstanceSetup.results_for_get_planned_volumes = InstanceSetup.results_for_get_planned_volumes[0, 3]
      InstanceSetup.results_for_attach_volume = InstanceSetup.results_for_attach_volume[0, 1]
      @mock_vm.results_for_disks = @mock_vm.results_for_disks[0, 2]
      @mock_vm.results_for_volumes = @mock_vm.results_for_volumes[0, 2]
      @mock_vm.results_for_partitions = @mock_vm.results_for_partitions[0, 1]

      # test.
      boot_to_stranded_with "Simulating vm format disk error."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when online disk fails' do
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      mock_core_api_attach_volume(planned_volumes)
      disks = mock_vm_disks
      volumes = mock_vm_volumes
      mock_vm_partitions(disks)
      mock_vm_format_disk(planned_volumes, disks, volumes)
      @mock_vm.results_for_online_disk = [lambda{ raise "Simulating vm online disk error." }]

      # tweak mocks to only give the results leading to call to format disk.
      InstanceSetup.results_for_get_planned_volumes = InstanceSetup.results_for_get_planned_volumes[0, 5]
      @mock_vm.results_for_volumes = @mock_vm.results_for_volumes[0, 4]

      # test.
      boot_to_stranded_with "Simulating vm online disk error."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

    it 'should strand when assign device fails' do
      planned_volumes = mock_core_api_get_planned_volumes
      mock_core_api_detach_volume(planned_volumes)
      mock_core_api_attach_volume(planned_volumes)
      disks = mock_vm_disks
      volumes = mock_vm_volumes
      mock_vm_partitions(disks)
      mock_vm_format_disk(planned_volumes, disks, volumes)
      mock_vm_online_disk(disks, volumes)
      @mock_vm.results_for_assign_device = [lambda{ raise "Simulating vm assign device error." }]

      # tweak mocks to only give the results leading to call to format disk.
      InstanceSetup.results_for_get_planned_volumes = InstanceSetup.results_for_get_planned_volumes[0, 5]

      # test.
      boot_to_stranded_with "Simulating vm assign device error."

      # assert all lists were consumed.
      InstanceSetup.assert_all_expectations_met
      @mock_vm.assert_all_expectations_met
    end

  else

    it 'should boot' do
      boot_to_operational
    end

  end

  it 'should strand when failing to prepare boot bundle' do
    boot_to_stranded_with "Failed to prepare boot bundle: Failed to retrieve boot scripts (Test)"
  end

end
