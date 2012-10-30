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

EXCLUDED_OHAI_PLUGINS = [ 'linux::block_device' ]

# Not for the feint of hearts:
# We need to disable the linux block device plugin because it can cause
# deadlocks (see description of LinuxBlockDevice below).
# So monkey patch Ohai to add the concept of excluded plugins and add
# the linux block device plugin to the excluded list.
require 'ohai'

module Ohai
  class System
    alias :require_all_plugins :require_plugin
    def require_plugin(plugin_name, force=false)
      unless EXCLUDED_OHAI_PLUGINS.include?(plugin_name)
        require_all_plugins(plugin_name, force)
      end
    end
  end
end

module RightScale

  # Preload content of /sys/block to avoid deadlocks when loading from
  # a different thread (issue with async IO and sysfs):
  # - File.read('/sys/block/...') will hang if run in a multithread ruby
  #   process because it will use async IO
  # - `cat /sys/block/...` will deadlock with the `uptime` command ran
  #   from agents's hearbeat callback
  class LinuxBlockDevice
    def self.info
      @@info
    end
    if RightSupport::Platform.linux? && File.exists?("/sys/block")
      @@info = Hash.new
      Dir["/sys/block/*"].each do |block_device_dir|
        dir = File.basename(block_device_dir)
        @@info[dir] = Hash.new
        %w{size removable}.each do |check|
          if File.exists?("/sys/block/#{dir}/#{check}")
            @@info[dir][check] = File.read("/sys/block/#{dir}/#{check}").chomp
          end
        end
        %w{model rev state timeout vendor}.each do |check|
          if File.exists?("/sys/block/#{dir}/device/#{check}")
            @@info[dir][check] = File.read("/sys/block/#{dir}/device/#{check}").chomp
          end
        end
      end
    end
  end

end
