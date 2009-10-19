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

provides "block_device"

# This is a fix for the Ohai Linux block device plugin which is not EventMachine-safe
# because Linux sysfs does not support nonblocking reads and the Ruby IO object's
# "nonblocking" read hangs the VM when reading from a sysfs file handle.
if File.exists?("/sys/block")
  block = Mash.new
  Dir["/sys/block/*"].each do |block_device_dir|
    dir = File.basename(block_device_dir)
    block[dir] = Mash.new
    %w{size removable}.each do |check|
      if File.exists?("/sys/block/#{dir}/#{check}")
        block[dir][check] = `cat /sys/block/#{dir}/#{check}`.chomp
      end
    end
    %w{model rev state timeout vendor}.each do |check|
      if File.exists?("/sys/block/#{dir}/device/#{check}")
        block[dir][check] = `cat /sys/block/#{dir}/device/#{check}`.chomp
      end
    end
  end
  block_device block
end