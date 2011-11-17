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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'clouds', 'metadata_sources', 'file_metadata_source')
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'clouds', 'metadata_sources', 'config_drive_metadata_source')

module RightScale
  module ConfigDriveMetadataSourceSpec

    CONFIG_DRIVE_SIZE_IN_SECTORS = 1048576
    CONFIG_DRIVE_DEVICE = "xvdz"
    CONFIG_DRIVE_MOUNTPOINT = "/tmp/rl_test/mnt/configdrive"
    SYS_BLOCK_DIR_PATH = "/tmp/rl_test/sys/block"

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
        safe_mkdir(SYS_BLOCK_DIR_PATH)
        safe_mkdir(CONFIG_DRIVE_MOUNTPOINT)
        File.open(File.join(CONFIG_DRIVE_MOUNTPOINT, 'userdata'), 'w') {|f| f.write("foobarbaz")}

        # A couple ramdisks, typically there are a lot more, but let's not make the unit test take longer than necesary eh?
        2.times do |i|
          ram_path = File.join(SYS_BLOCK_DIR_PATH, "ram#{i}")
          safe_mkdir(ram_path)
          File.open(File.join(ram_path, 'size'), 'w') {|f| f.write('131072')}
        end

        # Again, a few to simulate the root and a couple attached disks
        some_random_sector_counts = [16777216,4194304,131072]
        ('a'..'c').each_with_index do |l,i|
          disk_path = File.join(SYS_BLOCK_DIR_PATH, "xvd#{l}")
          safe_mkdir(disk_path)
          File.open(File.join(disk_path, 'size'), 'w') {|f| f.write("#{some_random_sector_counts[i]}")}
        end

        safe_mkdir(File.join(SYS_BLOCK_DIR_PATH, CONFIG_DRIVE_DEVICE))
        File.open(File.join(SYS_BLOCK_DIR_PATH, CONFIG_DRIVE_DEVICE, 'size'), 'w') {|f| f.write("#{CONFIG_DRIVE_SIZE_IN_SECTORS}")}

        # We're just throwing the logs away during tests, could potentially leverage fetch_runner, but it seems
        # like overkill
        logger = flexmock("log")
        logger.should_receive(:debug)
        logger.should_receive(:error)

        @user_metadata_source = ::RightScale::MetadataSources::ConfigDriveMetadataSource.new({
          :logger                           => logger,
          :sys_block_dir_path               => SYS_BLOCK_DIR_PATH,
          :config_drive_mountpoint          => CONFIG_DRIVE_MOUNTPOINT,
          :config_drive_sector_count        => CONFIG_DRIVE_SIZE_IN_SECTORS
        })
      end

      def teardown_metadata_provider
          FileUtils::rm_rf("/tmp/rl_test")
      end

      it 'can find and mount a device given it\'s sector count' do
        mount_resp = <<EOF
/dev/sda1 /
EOF
        mount_popen_obj = flexmock("foo")
        mount_popen_obj.should_receive(:read).at_least.once.and_return(mount_resp)

        flexmock(IO).should_receive(:popen).at_least.once.with("mount",Proc).and_yield(mount_popen_obj)
        flexmock(IO).should_receive(:popen).at_least.once.with("mount -t fat32 /dev/xvdz /tmp/rl_test/mnt/configdrive",Proc).and_return(0)

        @user_metadata_source.query('user_metadata').should === "foobarbaz"
      end

      it 'does not (re)mount the config drive if it\'s already mounted' do
        mount_resp = <<EOF
/dev/sda1 /
/dev/xvdz /tmp/rl_test/mnt/configdrive
EOF
        mount_popen_obj = flexmock("foo")
        mount_popen_obj.should_receive(:read).at_least.once.and_return(mount_resp)

        flexmock(IO).should_receive(:popen).at_least.once.with("mount",Proc).and_yield(mount_popen_obj)
        flexmock(IO).should_receive(:popen).never.with("mount -t fat32 /dev/xvdz /tmp/rl_test/mnt/configdrive",Proc).and_return(0)

        @user_metadata_source.query('user_metadata').should === "foobarbaz"
      end

    end

  end
end