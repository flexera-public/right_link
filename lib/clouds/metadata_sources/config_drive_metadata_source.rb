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

require File.normalize_path(File.expand_path('../file_metadata_source', __FILE__))

module RightScale
  module MetadataSources
    class ConfigDriveMetadataSource < FileMetadataSource

      DEFAULT_DEV_DISK_DIR_PATH       = "/dev/disk"
      DEFAULT_CONFIG_DRIVE_MOUNTPOINT = "/mnt/configdrive"

      attr_accessor :config_drive_label, :config_drive_size_in_blocks, :config_drive_mountpoint, :config_drive_uuid

      def initialize(options)
        raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]
        raise ArgumentError, "options[:config_drive_size_in_blocks] is required" unless @config_drive_size_in_blocks = options[:config_drive_size_in_blocks]

        @config_drive_mountpoint      = options[:config_drive_mountpoint] || DEFAULT_CONFIG_DRIVE_MOUNTPOINT
        @config_drive_uuid            = options[:config_drive_uuid]
        @config_drive_filesystem      = options[:config_drive_filesystem]
        @config_drive_label           = options[:config_drive_label]

        super(options)
      end

      def query(path)
        mount_config_drive

        super(path)
      end

      private

      def blocking_popen(command)
        IO.popen(command) do |io|
          io.read
        end
      end

      def find_device
        results = []
        success = []
        default = ""

        if RightScale::Platform.windows?
          # Probably some WMI magic here?
        else
          by_size = '/dev/'+blocking_popen("cat /proc/partitions | grep #{@config_drive_size_in_blocks} | awk '{print $4}'")
          by_size.strip!
          default = by_size
          results << by_size
          results << (@config_drive_uuid ? blocking_popen("blkid -t UUID=#{@config_drive_uuid} -o device").strip : by_size)
          results << (@config_drive_filesystem ? blocking_popen("blkid -t TYPE=#{@config_drive_filesystem} -o device").strip : by_size)
          results << (@config_drive_label ? blocking_popen("blkid -t LABEL=#{@config_drive_label} -o device").strip : by_size)
        end

        results.length.times do |i|
          success << default
        end

        success == results ? default : nil
      end

      def mount_config_drive
        device = find_device

        # Raise or log and exit?
        if !device || device.empty?
          @logger.error("No config drive device found.")
          return
        end

        if RightScale::Platform.windows?
          # Finding devices (in windows) - http://stackoverflow.com/questions/3258518/ruby-get-available-disk-drives
        else
          mount_list_output = blocking_popen('mount')
          if !(mount_list_output =~ /#{@config_drive_mountpoint}/)
            FileUtils.mkdir_p(@config_drive_mountpoint) unless File.directory? @config_drive_mountpoint
            mount_output = blocking_popen("mount -t vfat #{device} #{@config_drive_mountpoint}")
            unless $?.success?
              @logger.error("Unable to mount config drive to \"#{@config_drive_mountpoint}\" with device \"#{device}\"; Exit Status: #{$?.exitstatus}\nError: #{mount_output}")
            end
          end
        end
      end

    end
  end
end