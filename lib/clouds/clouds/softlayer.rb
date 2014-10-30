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

SL_METADATA_DIR = File.join(RightScale::Platform.filesystem.spool_dir, name.to_s, 'openstack') if ::RightScale::Platform.linux?
SL_METADATA_DIR = File.join(ENV['ProgramW6432'], 'RightScale', 'Mount', 'Softlayer', 'openstack').gsub('/', '\\') if ::RightScale::Platform.windows?

# dependencies.
metadata_source 'metadata_sources/file_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

abbreviation :sl

# Parses softlayer network interface file for IP address
#
# === Parameters
# config(Hash):: Hash with 'content_path' key, that points to file
# result(Hash):: Hash-like leaf value
#
# === Return
# Always true
def populate_ips(config, result)
  return true unless config.is_a?(Hash) && config.has_key?("content_path")
  config_file = File.join(SL_METADATA_DIR, config["content_path"])
  addr_regexp = /^address ([0-9\.]*)$/m
  private_regexp = /\A(10\.|192\.168\.|172\.1[6789]\.|172\.2.\.|172\.3[01]\.)/
  File.open(config_file).each do |line|
    address = addr_regexp.match(line)
    next unless address
    result[ address[1]=~ private_regexp ? 'local_ip' : 'public_ip' ] = address[1]
  end if File.exists?(config_file)
  return true
end

# Parses softlayer user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_cloud_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  parsed_data = nil
  begin
    parsed_data = JSON.parse(data.strip)
  rescue Exception => e
    logger.error("#{e.class}: #{e.message}")
  end
  network_config = parsed_data.delete('network_config')
  populate_ips(network_config, result) if network_config
  parsed_data.each do |k,v|
    result[k] = v
  end
  result
end

# Parses softlayer user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, '&', result)
  result
end

# defaults.
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
default_option([:metadata_source, :user_metadata_source_file_path], File.join(SL_METADATA_DIR, 'latest', 'user_data'))

default_option([:cloud_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_cloud_metadata_leaf))
default_option([:metadata_source, :cloud_metadata_source_file_path], File.join(SL_METADATA_DIR, 'latest', 'meta_data.json'))
default_option([:cloud_metadata, :metadata_tree_climber, :has_children_override], lambda { |*| false } )
default_option([:cloud_metadata, :metadata_writers, :ruby_metadata_writer, :generation_command], cloud_metadata_generation_command)
