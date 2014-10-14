#
# Copyright (c) 2011 RightScale Inc
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

require 'json'

require File.expand_path('../spec_helper', __FILE__)
require File.expand_path('../../../lib/clouds/metadata_sources/config_drive_metadata_source', __FILE__)

module RightScale
  module ConfigDriveMetadataSourceSpec

    TEMP_DIR                        = ::File.join(::RightScale::Platform.filesystem.temp_dir, "ConfigDriveMetadataSourceSpec-96ba62cb36bf46b497ac8b1bbd0080c1")
    CONFIG_DRIVE_UUID               = "681B-8C5D"
    CONFIG_DRIVE_FILESYSTEM         = "vfat"
    CONFIG_DRIVE_LABEL              = "METADATA"
    CONFIG_DRIVE_DEVICE             = "xvdh1"
    CONFIG_DRIVE_MOUNTPOINT         = ::File.join(TEMP_DIR, "mnt/configdrive")
    USER_METADATA_JSON              = '["RS_rn_url=amqp:\/\/1234567890@broker1-2.rightscale.com\/right_net&RS_rn_id=1234567890&RS_server=my.rightscale.com&RS_rn_auth=1234567890&RS_api_url=https:\/\/my.rightscale.com\/api\/inst\/ec2_instances\/1234567890&RS_rn_host=:1,broker1-1.rightscale.com:0&RS_version=5.6.5&RS_sketchy=sketchy4-2.rightscale.com&RS_token=1234567890"]'

    describe RightScale::MetadataSources::ConfigDriveMetadataSource do

      before(:all) do
        setup_metadata_provider
      end

      after(:all) do
        teardown_metadata_provider
      end

      def safe_mkdir(dir)
        FileUtils::rm_rf(dir) if File.directory?(dir)
        FileUtils::mkdir_p(dir)
      end

      def setup_metadata_provider
        safe_mkdir(CONFIG_DRIVE_MOUNTPOINT)
        File.open(File.join(CONFIG_DRIVE_MOUNTPOINT, 'userdata'), 'w') {|f| f.write(USER_METADATA_JSON)}

        # We're just throwing the logs away during tests, could potentially leverage fetch_runner, but it seems
        # like overkill
        logger = flexmock("log")
        logger.should_receive(:debug)
        logger.should_receive(:error)
        logger.should_receive(:warn)

        @user_metadata_source = ::RightScale::MetadataSources::ConfigDriveMetadataSource.new({
          :logger                         => logger,
          :config_drive_mountpoint        => CONFIG_DRIVE_MOUNTPOINT,
          :config_drive_uuid              => CONFIG_DRIVE_UUID,
          :config_drive_filesystem        => CONFIG_DRIVE_FILESYSTEM,
          :config_drive_label             => CONFIG_DRIVE_LABEL,
          :cloud_metadata_root_path       => ::RightScale::Cloud::DEFAULT_CLOUD_METADATA_ROOT_PATH,
          :user_metadata_root_path        => ::RightScale::Cloud::DEFAULT_USER_METADATA_ROOT_PATH,
          :user_metadata_source_file_path => File.join(CONFIG_DRIVE_MOUNTPOINT, 'userdata')
        })
      end

      def teardown_metadata_provider
        FileUtils::rm_rf(TEMP_DIR)
      end

      context :mount_config_drive do
        before(:each) do
          @volume_manager = flexmock("volume_manager")
          flexmock(::RightScale::Platform).should_receive(:volume_manager).and_return(@volume_manager)
        end

        it 'raises config_drive_error if no device is found' do
          timeint = Time.now.to_i
          @volume_manager.should_receive(:volumes => [], :disks => [])
          flexmock(Time).should_receive(:now).twice.and_return(timeint, timeint + (60*11))

          lambda { @user_metadata_source.mount_config_drive }.should raise_error(RightScale::MetadataSources::ConfigDriveMetadataSource::ConfigDriveError)
        end

        it 'creates the config drive mountpoint if it does not exist' do
          @volume_manager.should_receive(:volumes => [{:device => "/dev/xvda1"}], :mount_volume => true, :assign_device => true)

          flexmock(File).should_receive(:directory?).at_least.once.with(CONFIG_DRIVE_MOUNTPOINT).and_return(false)
          flexmock(FileUtils).should_receive(:mkdir_p).at_least.once.with(CONFIG_DRIVE_MOUNTPOINT)

          @user_metadata_source.mount_config_drive
        end

        def test_mount_config_drive
          flexmock(::RightScale::Platform).should_receive(:linux?).and_return(false)
          @volume_manager.should_receive(:volumes).times(5).and_return([],[],[],[],[{:device => "/dev/xvdh1"}])
          flexmock(Kernel).should_receive(:sleep).times(4)
          @user_metadata_source.mount_config_drive
        end

        context 'Windows platform' do
          before(:each) do
            flexmock(::RightScale::Platform).should_receive(:linux?).and_return(false)
            flexmock(::RightScale::Platform).should_receive(:windows?).and_return(true)
          end
          it 'waits for the config drive to be attached' do
            @volume_manager.should_receive(:assign_device).once.and_return(true)
            @volume_manager.should_receive(:disks).times(4).and_return([],[],[],[])
            test_mount_config_drive
          end

          it 'does not bother to online disks if the volume is found' do
            @volume_manager.should_receive(:volumes).once.and_return([{:index => 0}])
            @volume_manager.should_receive(:assign_device).once.and_return(true)
            @user_metadata_source.mount_config_drive
          end

          it 'checks offline disks one at a time for the desired volume until it is found' do
            # Simulates two iterations of the loop which looks for the config drive
            # the first iteration returns one offline disk and no matching volumes.
            # The second iteration returns two offlined disk (simulating a new disk being attached and discovered)
            # which then has the requested volume associated with it
            @volume_manager.should_receive(:volumes).times(5).and_return([],[],[],[],[{:index => 0}])
            @volume_manager.should_receive(:disks).times(2).and_return([{:index => 1}], [{:index => 1},{:index => 2}])
            @volume_manager.should_receive(:online_disk).times(3).and_return(true)
            @volume_manager.should_receive(:offline_disk).times(2).and_return(true)
            @volume_manager.should_receive(:assign_device).once.and_return(true)
            flexmock(Kernel).should_receive(:sleep).times(1)
            @user_metadata_source.mount_config_drive
          end
        end

        context 'Linux platform' do
          before(:each) do
            flexmock(::RightScale::Platform).should_receive(:linux?).and_return(true)
            flexmock(::RightScale::Platform).should_receive(:windows?).and_return(false)
          end
          it 'waits for the config drive to be attached' do
            @volume_manager.should_receive(:mount_volume).once.and_return(true)
            test_mount_config_drive
          end
        end
      end
    end

  end
end