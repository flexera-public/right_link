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
require File.join(File.dirname(__FILE__), 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'clouds', 'metadata_sources', 'config_drive_metadata_source')

module RightScale
  module ConfigDriveMetadataSourceSpec

    CONFIG_DRIVE_SIZE_IN_BLOCKS   = 62464
    CONFIG_DRIVE_UUID             = "681B-8C5D"
    CONFIG_DRIVE_FILESYSTEM       = "vfat"
    CONFIG_DRIVE_LABEL            = "METADATA"
    CONFIG_DRIVE_DEVICE           = "xvdh1"
    CONFIG_DRIVE_MOUNTPOINT       = "/tmp/rl_test/mnt/configdrive"
    DEV_DISK_DIR_PATH             = "/tmp/rl_test/dev/disk"
    USER_METADATA_JSON            = '["RS_rn_url=amqp:\/\/1234567890@broker1-2.rightscale.com\/right_net&RS_rn_id=1234567890&RS_server=my.rightscale.com&RS_rn_auth=1234567890&RS_api_url=https:\/\/my.rightscale.com\/api\/inst\/ec2_instances\/1234567890&RS_rn_host=:1,broker1-1.rightscale.com:0&RS_version=5.6.5&RS_sketchy=sketchy4-2.rightscale.com&RS_token=1234567890"]'

    describe RightScale::MetadataSources::ConfigDriveMetadataSource do

      before(:all) do
        setup_metadata_provider
      end

      after(:all) do
        teardown_metadata_provider
      end

      def safe_mkdir(dir)
        if File.directory? dir
          FileUtils::rm_rf(dir)
        else
          FileUtils::mkdir_p(dir)
        end

      end

      def setup_metadata_provider
        safe_mkdir(CONFIG_DRIVE_MOUNTPOINT)
        File.open(File.join(CONFIG_DRIVE_MOUNTPOINT, 'userdata'), 'w') {|f| f.write(USER_METADATA_JSON)}

        # We're just throwing the logs away during tests, could potentially leverage fetch_runner, but it seems
        # like overkill
        logger = flexmock("log")
        logger.should_receive(:debug)
        logger.should_receive(:error)

        @user_metadata_source = ::RightScale::MetadataSources::ConfigDriveMetadataSource.new({
          :logger                         => logger,
          :config_drive_mountpoint        => CONFIG_DRIVE_MOUNTPOINT,
          :config_drive_uuid              => CONFIG_DRIVE_UUID,
          :config_drive_filesystem        => CONFIG_DRIVE_FILESYSTEM,
          :config_drive_label             => CONFIG_DRIVE_LABEL,
          :config_drive_size_in_blocks    => CONFIG_DRIVE_SIZE_IN_BLOCKS,
          :user_metadata_source_file_path => File.join(CONFIG_DRIVE_MOUNTPOINT, 'userdata')
        })
      end

      def teardown_metadata_provider
          FileUtils::rm_rf("/tmp/rl_test")
      end

      it 'can find and mount a device given all searchable properties' do
        mount_resp = <<EOF
/dev/sda1 /

EOF

        device_path = <<EOF
/dev/#{CONFIG_DRIVE_DEVICE}

EOF

        mount_popen_obj = flexmock("foo")
        mount_popen_obj.should_receive(:read).at_least.once.and_return(mount_resp)

        cat_proc_mock = flexmock("cat_proc_mock")
        cat_proc_mock.should_receive(:read).at_least.once.and_return(CONFIG_DRIVE_DEVICE)

        blkid_mock = flexmock("blkid_mock")
        blkid_mock.should_receive(:read).times(3).and_return(device_path)

        flexmock(IO).should_receive(:popen).at_least.once.with("cat /proc/partitions | grep #{CONFIG_DRIVE_SIZE_IN_BLOCKS} | awk '{print $4}'",Proc).and_yield(cat_proc_mock)
        flexmock(IO).should_receive(:popen).at_least.once.with("blkid -t UUID=#{CONFIG_DRIVE_UUID} -o device",Proc).and_yield(blkid_mock)
        flexmock(IO).should_receive(:popen).at_least.once.with("blkid -t TYPE=#{CONFIG_DRIVE_FILESYSTEM} -o device",Proc).and_yield(blkid_mock)
        flexmock(IO).should_receive(:popen).at_least.once.with("blkid -t LABEL=#{CONFIG_DRIVE_LABEL} -o device",Proc).and_yield(blkid_mock)

        flexmock(IO).should_receive(:popen).at_least.once.with("mount",Proc).and_yield(mount_popen_obj)
        flexmock(IO).should_receive(:popen).at_least.once.with("mount -t vfat /dev/#{CONFIG_DRIVE_DEVICE} /tmp/rl_test/mnt/configdrive",Proc).and_return(0)

        @user_metadata_source.query('user_metadata').should === USER_METADATA_JSON
      end

#      it 'does not (re)mount the config drive if it\'s already mounted' do
#        mount_resp = <<EOF
#/dev/sda1 /
#/dev/xvdz /tmp/rl_test/mnt/configdrive
#EOF
#        mount_popen_obj = flexmock("foo")
#        mount_popen_obj.should_receive(:read).at_least.once.and_return(mount_resp)
#
#        flexmock(IO).should_receive(:popen).at_least.once.with("mount",Proc).and_yield(mount_popen_obj)
#        flexmock(IO).should_receive(:popen).never.with("mount -t vfat /dev/xvdz /tmp/rl_test/mnt/configdrive",Proc).and_return(0)
#
#        @user_metadata_source.query('user_metadata').should === JSON.parse(USER_METADATA_JSON)
#      end

      it 'creates the config drive mountpoint if it does not exist' do
        flexmock(File).should_receive(:directory?).at_least.once.with(CONFIG_DRIVE_MOUNTPOINT).and_return(false)
        flexmock(FileUtils).should_receive(:mkdir_p).at_least.once.with(CONFIG_DRIVE_MOUNTPOINT)

        @user_metadata_source.query('user_metadata')
      end
    end

  end
end