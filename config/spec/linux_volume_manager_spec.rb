#
# Copyright (c) 2009-2011 RightScale Inc
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

basedir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require File.join(basedir, 'spec', 'spec_helper')

if RightScale::Platform.linux?
  describe RightScale::Platform do
    before(:all) do
      @platform = RightScale::Platform
    end

    context :volume_manager do
      context :parse_volumes do
        it 'can parse volumes from blkid output' do
          blkid_resp = <<EOF
/dev/xvdh1: SEC_TYPE="msdos" LABEL="METADATA" UUID="681B-8C5D" TYPE="vfat"
/dev/xvdb1: LABEL="SWAP-xvdb1" UUID="d51fcca0-6b10-4934-a572-f3898dfd8840" TYPE="swap"
/dev/xvda1: UUID="f4746f9c-0557-4406-9267-5e918e87ca2e" TYPE="ext3"
/dev/xvda2: UUID="14d88b9e-9fe6-4974-a8d6-180acdae4016" TYPE="ext3"
EOF
          volume_hash_ary = [
            {:device => "/dev/xvdh1", :sec_type => "msdos", :label => "METADATA", :uuid => "681B-8C5D", :type => "vfat", :filesystem => "vfat"},
            {:device => "/dev/xvdb1", :label => "SWAP-xvdb1", :uuid => "d51fcca0-6b10-4934-a572-f3898dfd8840", :type => "swap", :filesystem => "swap"},
            {:device => "/dev/xvda1", :uuid => "f4746f9c-0557-4406-9267-5e918e87ca2e", :type => "ext3", :filesystem => "ext3"},
            {:device => "/dev/xvda2", :uuid => "14d88b9e-9fe6-4974-a8d6-180acdae4016", :type => "ext3", :filesystem => "ext3"}
          ]

          @platform.volume_manager.parse_volumes(blkid_resp).should == volume_hash_ary
        end

        it 'raises a parser error when blkid output is malformed' do
          blkid_resp = 'foobarbz'

          lambda { @platform.volume_manager.parse_volumes(blkid_resp) }.should raise_error(RightScale::Platform::Linux::VolumeManager::ParserError)
        end

        it 'returns an empty list of volumes when blkid output is empty' do
          blkid_resp = ''

          @platform.volume_manager.parse_volumes(blkid_resp).should == []
        end

        it 'can filter results with only one condition' do
          blkid_resp = <<EOF
/dev/xvdh1: SEC_TYPE="msdos" LABEL="METADATA" UUID="681B-8C5D" TYPE="vfat"
/dev/xvdb1: LABEL="SWAP-xvdb1" UUID="d51fcca0-6b10-4934-a572-f3898dfd8840" TYPE="swap"
/dev/xvda1: UUID="f4746f9c-0557-4406-9267-5e918e87ca2e" TYPE="ext3"
/dev/xvda2: UUID="14d88b9e-9fe6-4974-a8d6-180acdae4016" TYPE="ext3"
EOF
          volume_hash_ary = [
            {:device => "/dev/xvdh1", :sec_type => "msdos", :label => "METADATA", :uuid => "681B-8C5D", :type => "vfat", :filesystem => "vfat"}
          ]

          condition = {:uuid => "681B-8C5D"}

          @platform.volume_manager.parse_volumes(blkid_resp, condition).should == volume_hash_ary
        end

        it 'can filter results with many conditions' do
          blkid_resp = <<EOF
/dev/xvdh1: SEC_TYPE="msdos" LABEL="METADATA" UUID="681B-8C5D" TYPE="vfat"
/dev/xvdb1: LABEL="SWAP-xvdb1" UUID="d51fcca0-6b10-4934-a572-f3898dfd8840" TYPE="swap"
/dev/xvda1: UUID="f4746f9c-0557-4406-9267-5e918e87ca2e" TYPE="ext3"
/dev/xvda2: UUID="14d88b9e-9fe6-4974-a8d6-180acdae4016" TYPE="ext3"
EOF
          volume_hash_ary = [
            {:device => "/dev/xvda1", :uuid => "f4746f9c-0557-4406-9267-5e918e87ca2e", :type => "ext3", :filesystem => "ext3"},
            {:device => "/dev/xvda2", :uuid => "14d88b9e-9fe6-4974-a8d6-180acdae4016", :type => "ext3", :filesystem => "ext3"}
          ]

          condition = {:filesystem => "ext3"}

          @platform.volume_manager.parse_volumes(blkid_resp, condition).should == volume_hash_ary
        end
      end

      context :mount_volume do
        it 'mounts the specified volume if it is not already mounted' do
          mount_resp = <<EOF
/dev/xvda2 on / type ext3 (rw,noatime,errors=remount-ro)
proc on /proc type proc (rw,noexec,nosuid,nodev)
EOF

          mount_popen_mock = flexmock(:read => mount_resp)
          flexmock(IO).should_receive(:popen).with('mount',Proc).once.and_yield(mount_popen_mock)
          flexmock(IO).should_receive(:popen).with('mount -t vfat /dev/xvdh1 /var/spool/softlayer',Proc).once.and_yield(flexmock(:read => ""))

          @platform.volume_manager.mount_volume({:device => "/dev/xvdh1", :filesystem => "vfat"}, "/var/spool/softlayer")
        end

        it 'does not attempt to re-mount the volume' do
          mount_resp = <<EOF
/dev/xvda2 on / type ext3 (rw,noatime,errors=remount-ro)
proc on /proc type proc (rw,noexec,nosuid,nodev)
/dev/xvdh1 on /var/spool/softlayer type vfat (rw) [METADATA]
EOF

          mount_popen_mock = flexmock(:read => mount_resp)
          flexmock(IO).should_receive(:popen).with('mount',Proc).once.and_yield(mount_popen_mock)
          flexmock(IO).should_receive(:popen).with('mount -t vfat /dev/xvdh1 /var/spool/softlayer',Proc).never.and_yield(flexmock(:read => ""))

          @platform.volume_manager.mount_volume({:device => "/dev/xvdh1", :filesystem => "vfat"}, "/var/spool/softlayer")
        end

        it 'raises argument error when the volume parameter is not a hash' do
          lambda { @platform.volume_manager.mount_volume("", "") }.should raise_error(ArgumentError)
        end

        it 'raises argument error when the volume parameter is a hash but does not contain :device' do
          lambda { @platform.volume_manager.mount_volume({}, "") }.should raise_error(ArgumentError)
        end

        it 'raises volume error when the device is already mounted to a different mountpoint' do
          mount_resp = <<EOF
/dev/xvda2 on / type ext3 (rw,noatime,errors=remount-ro)
proc on /proc type proc (rw,noexec,nosuid,nodev)
none on /sys type sysfs (rw,noexec,nosuid,nodev)
none on /sys/kernel/debug type debugfs (rw)
none on /sys/kernel/security type securityfs (rw)
none on /dev type devtmpfs (rw,mode=0755)
none on /dev/pts type devpts (rw,noexec,nosuid,gid=5,mode=0620)
none on /dev/shm type tmpfs (rw,nosuid,nodev)
none on /var/run type tmpfs (rw,nosuid,mode=0755)
none on /var/lock type tmpfs (rw,noexec,nosuid,nodev)
none on /lib/init/rw type tmpfs (rw,nosuid,mode=0755)
/dev/xvda1 on /boot type ext3 (rw,noatime)
/dev/xvdh1 on /mnt type vfat (rw) [METADATA]
EOF

          mount_popen_mock = flexmock(:read => mount_resp)
          flexmock(IO).should_receive(:popen).with('mount',Proc).and_yield(mount_popen_mock)

          lambda { @platform.volume_manager.mount_volume({:device => "/dev/xvdh1"}, "/var/spool/softlayer")}.should raise_error(RightScale::Platform::Linux::VolumeManager::VolumeError)
        end

        it 'raises volume error when a different device is already mounted to the specified mountpoint' do
          mount_resp = <<EOF
/dev/xvda2 on / type ext3 (rw,noatime,errors=remount-ro)
proc on /proc type proc (rw,noexec,nosuid,nodev)
none on /sys type sysfs (rw,noexec,nosuid,nodev)
none on /sys/kernel/debug type debugfs (rw)
none on /sys/kernel/security type securityfs (rw)
none on /dev type devtmpfs (rw,mode=0755)
none on /dev/pts type devpts (rw,noexec,nosuid,gid=5,mode=0620)
none on /dev/shm type tmpfs (rw,nosuid,nodev)
none on /var/run type tmpfs (rw,nosuid,mode=0755)
none on /var/lock type tmpfs (rw,noexec,nosuid,nodev)
none on /lib/init/rw type tmpfs (rw,nosuid,mode=0755)
/dev/xvda1 on /boot type ext3 (rw,noatime)
/dev/xvdh2 on /var/spool/softlayer type vfat (rw) [METADATA]
EOF

          mount_popen_mock = flexmock(:read => mount_resp)
          flexmock(IO).should_receive(:popen).with('mount',Proc).and_yield(mount_popen_mock)

          lambda { @platform.volume_manager.mount_volume({:device => "/dev/xvdh1"}, "/var/spool/softlayer")}.should raise_error(RightScale::Platform::Linux::VolumeManager::VolumeError)
        end
      end
    end
  end
end