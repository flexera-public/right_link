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

      class ConfigDriveError < Exception; end

      DEFAULT_DEV_DISK_DIR_PATH       = "/dev/disk"
      DEFAULT_CONFIG_DRIVE_MOUNTPOINT = "/mnt/configdrive"

      attr_accessor :config_drive_label, :config_drive_mountpoint, :config_drive_uuid, :config_drive_filesystem

      def initialize(options)
        raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]

        @config_drive_mountpoint      = options[:config_drive_mountpoint] || DEFAULT_CONFIG_DRIVE_MOUNTPOINT
        @config_drive_uuid            = options[:config_drive_uuid]
        @config_drive_filesystem      = options[:config_drive_filesystem]
        @config_drive_label           = options[:config_drive_label]

        if @config_drive_uuid.nil? & @config_drive_label.nil? & @config_drive_filesystem.nil?
          raise ArgumentError, "at least one of the following is required [options[:config_drive_label], options[:config_drive_filesystem],options[:config_drive_uuid]]"
        end

        super(options)
      end

      # Queries for metadata using the given path.
      #
      # === Parameters
      # path(String):: metadata path
      #
      # === Return
      # metadata(String):: query result
      #
      # === Raises
      # QueryFailed:: on any failure to query
      def query(path)
        mount_config_drive

        super(path)
      end

      # Mounts the configuration drive based on the provided parameters
      #
      # === Parameters
      #
      # === Return
      # always true
      #
      # === Raises
      # ConfigDriveError:: on failure to find a config drive
      # SystemCallError:: on failure to create the mountpoint
      # ArgumentError:: on invalid parameters
      # VolumeError:: on a failure to mount the device
      # ParserError:: on failure to parse volume list
      def mount_config_drive
        # These two conditions are available on *nix and windows
        conditions = {}
        conditions[:label] = @config_drive_label if @config_drive_label
        conditions[:filesystem] = @config_drive_filesystem if @config_drive_filesystem

        if ::RightScale::Platform.linux? && @config_drive_uuid
          conditions[:uuid] = @config_drive_uuid
        end

        timeout   = 60 * 10
        starttime = Time.now.to_i
        backoff   = [2,5,10]
        idx       = -1

        begin
          device_ary = ::RightScale::Platform.volume_manager.volumes(conditions)
          idx = idx + 1 unless idx == 2
          break if (Time.now.to_i - starttime) > timeout || device_ary.length > 0
          @logger.warn("Configuration drive device was not found.  Trying again in #{backoff[idx % backoff.length]} seconds.")
          Kernel.sleep(backoff[idx])
        end while device_ary.length == 0

        # REVIEW: Raise or log and exit?
        raise ConfigDriveError.new("Configuration drive device found. Conditions: #{conditions.inspect}") if device_ary.length == 0

        FileUtils.mkdir_p(@config_drive_mountpoint) unless File.directory? @config_drive_mountpoint

        if ::RightScale::Platform.linux?
          ::RightScale::Platform.volume_manager.mount_volume(device_ary[0], @config_drive_mountpoint)
        else
          ::RightScale::Platform.volume_manager.assign_device(device_ary[0][:index], @config_drive_mountpoint)
        end
        return true
      end

    end # ConfigDriveMetadataSource
  end # MetadataSources
end # RightScale