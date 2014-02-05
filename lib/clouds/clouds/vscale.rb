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

VSCALE_DEFINITION_VERSION = 0.2

CONFIG_DRIVE_MOUNTPOINT = "/mnt/metadata" unless ::RightScale::Platform.windows?
CONFIG_DRIVE_MOUNTPOINT = "a:\\" if ::RightScale::Platform.windows?

# dependencies.
metadata_source 'metadata_sources/file_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :vs




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

# userdata defaults
default_option([:metadata_source, :user_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'user.txt'))
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))

# cloud metadata defaults
default_option([:metadata_source, :cloud_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'meta.txt'))
default_option([:cloud_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
# vscale cloud_metadata is flat, so paths will never have children -- always return false
default_option([:cloud_metadata, :metadata_tree_climber, :has_children_override], method(:cloud_metadata_is_flat))

def requires_network_config?
  true
end


# Loads metadata from file into environment
#
def load_metadata
  begin
    load(::File.join(RightScale::AgentConfig.cloud_state_dir, 'meta-data.rb'))
  rescue Exception => e
    raise "FATAL: Cannot load metadata from #{meta_data_file}"
  end
end

# We return two lists of public IPs respectively private IPs to the GW. The is_private_ip
# test is used to sort the IPs of an instance into these lists. Not perfect but
# customizable.
#
# === Parameters
# ip(String):: an IPv4 address
#
# === Return
# result(Boolean):: true if format is okay, else false
def is_private_ipv4(ip)
  regexp = /\A(10\.|192\.168\.|172\.1[6789]\.|172\.2.\.|172\.3[01]\.)/
  ip =~ regexp
end
