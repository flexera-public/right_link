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


# Determines if the current instance is running on vsoup.
#
# === Return
# true if running on rackspace
def is_current_cloud?
  return true
end

def requires_network_config?
  true
end

# Updates the given node with cloud metadata details.
#
# We also do a bunch of VM configuration here.
# There is likely a better place we can do all this.
#
# === Return
# always true
def update_details
  details = {}
  details[:public_ips] = Array.new
  details[:private_ips] = Array.new

  load_metadata

  if platform.windows?
    # report new network interface configuration to ohai
    if ohai = @options[:ohai_node]
      ['Local Area Connection', 'Local Area Connection 2'].each do |device|
        ip = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, device)
        details[is_private_ipv4(ip) ? :local_ipv4 : :public_ipv4] = ip
      end
    end
  else
    # report new network interface configuration to ohai
    if ohai = @options[:ohai_node]
      # Pick up all IPs detected by ohai
      n = 0
      while (ip = ::RightScale::CloudUtilities.ip_for_interface(ohai, "eth#{n}")) != nil
        type = "public_ip"
        type = "private_ip" if is_private_ipv4(ip)
        details[type.to_sym] ||= ip      # store only the first found for type
        details["#{type}s".to_sym] << ip # but append all to the list
        n += 1
      end
    end
  end

  # Override with statically assigned IP (if specified)
  static_ips = ENV.collect { |k,v | v if k =~ /RS_STATIC_IP\d_ADDR/ }.compact
  static_ips.each do |static_ip|
    if is_private_ipv4(static_ip)
      details[:private_ip] ||= static_ip
      details[:private_ips] << static_ip
    else
      details[:public_ip] ||= static_ip
      details[:public_ips] << static_ip
    end
  end

  details
end

#
# Methods for update details
#

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
