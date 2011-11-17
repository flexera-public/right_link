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

module RightScale
  module MetadataSources
    class ConfigDriveMetadataSource < FileMetadataSource

      DEFAULT_SYS_BLOCK_DIR_PATH      = "/sys/block"
      DEFAULT_CONFIG_DRIVE_MOUNTPOINT = "/mnt/configdrive"

      attr_accessor :sys_block_dir_path, :config_drive_sector_count, :config_drive_mountpoint

      def initialize(options)
        raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]

        @sys_block_dir_path        = options[:sys_block_dir_path] || DEFAULT_SYS_BLOCK_DIR_PATH
        @config_drive_mountpoint   = options[:config_drive_mountpoint] || DEFAULT_CONFIG_DRIVE_MOUNTPOINT
        @config_drive_sector_count = options[:config_drive_sector_count]

        super(options.merge({
          :cloud_metadata_source_file_path => File.join(@config_drive_mountpoint, 'metadata'),
          :user_metadata_source_file_path => File.join(@config_drive_mountpoint, 'userdata')
        }))
      end

      def query(path)
        mount_config_drive()

        super(path)
      end

      private

      def blocking_popen(command)
        IO.popen(command) do |io|
          io.read
        end
      end

      def mount_config_drive
        if RightScale::Platform.windows?
          # Finding devices (in windows) - http://stackoverflow.com/questions/3258518/ruby-get-available-disk-drives
        else
          mount_list_output = blocking_popen('mount')
          if !(mount_list_output =~ /#{@config_drive_mountpoint}/)
            @logger.debug("Config drive not mounted at specified mountpoint.  Searching for config drive in \"#{@sys_block_dir_path}\"")
            Dir.entries(@sys_block_dir_path).each do |device|
              size_file_path = File.join(@sys_block_dir_path, device, 'size')
              if File.exists?(size_file_path)
                device_size = File.open(size_file_path, 'r') {|f| f.read }
                # We're only detecting the device's size in sectors, there are other properties we could look for
                # I.E. ro flag, fat32, removable flag
                if device_size == "#{@config_drive_sector_count}"
                  @logger.debug("Found config drive as device \"#{device}\", mounting.")
                  mount_output = blocking_popen("mount -t fat32 /dev/#{device} #{@config_drive_mountpoint}")
                  unless $?.success?
                    @logger.error("Unable to mount config drive to \"#{@config_drive_mountpoint}\" with device \"#{device}\"; Exit Status: #{$?.exitstatus}\nError: #{mount_output}")
                  end
                  return
                end
              end
            end
            # TODO: Should I be raising an exception here instead?
            @logger.error("No config drive was found with a sector count of \"#{@config_drive_sector_count}\"")
          end
        end

      end

    end
  end
end