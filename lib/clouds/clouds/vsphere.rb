#
# Copyright (c) 2013 RightScale Inc
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
require 'fileutils'

VSCALE_DEFINITION_VERSION = 0.3

CONFIG_DRIVE_MOUNTPOINT = File.join(RightScale::Platform.filesystem.spool_dir, 'vsphere')

# dependencies.
metadata_source 'metadata_sources/file_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :vs

# Assembles the command line needed to regenerate cloud metadata on demand.
def cloud_metadata_generation_command
  ruby_path = File.normalize_path(AgentConfig.ruby_cmd)
  rs_cloud_path = File.normalize_path(Gem.bin_path('right_link', 'cloud'))
  return "#{ruby_path} #{rs_cloud_path} --action write_cloud_metadata"
end

# Parses vsoup user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, "\n", result)
  result
end

def cloud_metadata_is_flat(clazz, path, query_result)
  false
end

# Extend clear_state method
# Clear any fetched metadata files
alias :_clear_state :clear_state
def clear_state
  _clear_state
  FileUtils.rm_rf(CONFIG_DRIVE_MOUNTPOINT) if File.directory?(CONFIG_DRIVE_MOUNTPOINT)
end

# userdata defaults
default_option([:metadata_source, :user_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'user.txt'))
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))

# cloud metadata defaults
default_option([:metadata_source, :cloud_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'meta.txt'))
default_option([:cloud_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
# vsphere cloud_metadata is flat, so paths will never have children -- always return false
default_option([:cloud_metadata, :metadata_tree_climber, :has_children_override], method(:cloud_metadata_is_flat))
default_option([:cloud_metadata, :metadata_writers, :ruby_metadata_writer, :generation_command], cloud_metadata_generation_command)

def requires_network_config?
  true
end