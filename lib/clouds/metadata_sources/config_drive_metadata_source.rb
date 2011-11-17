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

# Finding devices (in windows) - http://stackoverflow.com/questions/3258518/ruby-get-available-disk-drives

module RightScale
  module MetadataSources
    class ConfigDriveMetadataSource < MetadataSource

      DEFAULT_SYS_BLOCK_DIR_PATH      = "/sys/block"
      DEFAULT_CONFIG_DRIVE_MOUNTPOINT = "/mnt/configdrive"

      attr_accessor :sys_block_dir_path, :config_drive_sector_count, :config_drive_mountpoint, :file_metadata_source

      def initialize(options)
        raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]

        @sys_block_dir_path        = options[:sys_block_dir_path] || DEFAULT_SYS_BLOCK_DIR_PATH
        @config_drive_mountpoint   = options[:config_drive_mountpoint] || DEFAULT_CONFIG_DRIVE_MOUNTPOINT
        @config_drive_sector_count = options[:config_drive_sector_count]

        #@file_metadata_source = ::RightScale::MetadataSources::FileMetadataSource.new(options)
      end

      def query(path)
        mount_config_drive()
      end

      private

      def mount_config_drive
        mount_list_output = IO.popen('mount')
        if !(mount_list_output.readlines =~ /#{@config_drive_mountpoint}/)
          @logger.debug("Config drive not mounted at specified mountpoint.  Searching for config drive in #{@sys_block_dir_path}")
          Dir.entries(@sys_block_dir_path).each do |device|
            size_file_path = File.join(@sys_block_dir_path, device, 'size')
            if File.exists?(size_file_path)
              size_file = File.open(size_file_path, 'r')
              # We're only detecting the device's size in sectors, there are other properties we could look for
              # I.E. ro flag, fat32, removable flag
              if size_file.read == "#{@config_drive_sector_count}"
                @logger.debug("Found config drive as device #{device}, mounting.")
                # TODO: Probably want to check for errors while mounting
                IO.popen("mount -t fat32 /dev/#{device} #{@config_drive_mountpoint}")
              end
            end
          end
        end

      end

    end
  end
end