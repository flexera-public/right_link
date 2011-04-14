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
#

module RightScale

  # Represents any details of a planned volume which are needed by the instance
  # for volume management purposes. A planned volume is a blank, snapshotted or
  # existing volume which is associated with a server at launch time. It could
  # also represent a volume which is planned dynamically by the instance itself
  # as part of a script and which is then guaranteed to be properly managed if
  # the instance is stopped/started.
  class PlannedVolume

    include Serializable

    # (String) cloud-specific unique identifier for volume (relative to account
    # or global)
    attr_accessor :volume_id

    # (String) cloud-agnostic current known status of the volume. must be nil or
    # else one of the following:
    #  'pending', 'attached', 'attaching', 'detached', 'detaching', 'deleted'
    attr_accessor :volume_status

    # (String) cloud-specific device name for volume (relative to instance)
    attr_accessor :device_name

    # (Array of String) instance platform-specific mount point(s) for the
    # physical or virtual disk (which could have multiple partitions) associated
    # with the planned volume. not all partitions are formatted and/or have a
    # file system which is compatible with the instance's platform so only valid
    # partitions are associated with mount points.
    attr_accessor :mount_points

    def initialize(*args)
      @volume_id     = args[0] if args.size > 0
      @device_name   = args[1] if args.size > 1
      @mount_points  = args[2] if args.size > 2
      @volume_status = args[3] if args.size > 3
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @volume_id, @device_name, @mount_points, @volume_status ]
    end

    # Determines if this object is valid.
    #
    # === Return
    # result(Boolean):: true if this object is valid, false if required fields are nil or empty
    def is_valid?
      result = false == is_blank?(@volume_id) &&
               false == is_blank?(@device_name) &&
               false == is_blank?(@volume_status) &&
               false == is_blank?(@mount_points) &&
               nil == @mount_points.find { |mount_point| is_blank?(mount_point) }
      return result
    end

    private

    # Determines if the given value is nil or empty.
    #
    # === Parameters
    # value(Object):: any value
    #
    # === Return
    # true if value is nil or empty
    def is_blank?(value)
      value.nil? || value.empty?
    end

  end
end
