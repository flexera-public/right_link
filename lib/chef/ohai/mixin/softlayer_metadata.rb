#
# Copyright (c) 2010-2014 RightScale Inc
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

require 'json'

module ::Ohai::Mixin::SoftlayerMetadata

  SL_METADATA_DIR = '/var/spool/softlayer'

  # Prepare cloud metadata
  # === Parameters
  #
  # === Return
  # Hash
    def fetch_metadata
    metadata = cloud_metadata
    return metadata unless metadata
    network_config = metadata.delete('network_config')
    populate_ips(network_config, metadata) if network_config
    return metadata
  end

  private
  # Parse cloud metadata json file.
  # === Parameters
  #
  # === Return
  # Hash
  def cloud_metadata
    meta_data_file = File.join(SL_METADATA_DIR,'openstack', 'latest', 'meta_data.json')
    raise "Meta data file - #{meta_data_file} is missing" unless File.exists?(meta_data_file)
    metadata = ::JSON.parse(File.read(meta_data_file)) rescue nil
    return metadata
  end

  # Parses softlayer network interface file for IP address
  #
  # === Parameters
  # config(Hash):: Hash with 'content_path' key, that points to file
  # metadata(Hash):: Hash-like leaf value
  #
  # === Return
  # Always true
  def populate_ips(config, metadata)
    return true unless config.is_a?(Hash) && config.has_key?("content_path")
    config_file = File.join(SL_METADATA_DIR,'openstack', config["content_path"])
    addr_regexp = /^address ([0-9\.]*)$/m
    private_regexp = /\A(10\.|192\.168\.|172\.1[6789]\.|172\.2.\.|172\.3[01]\.)/
    File.open(config_file).each do |line|
      address = addr_regexp.match(line)
      next unless address
      metadata[ address[1]=~ private_regexp ? 'local_ipv4' : 'public_ipv4' ] = address[1]
    end if File.exists?(config_file)
    return true
  end

end
