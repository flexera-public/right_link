#
# Copyright (c) 2012 RightScale Inc
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

# host/port are constants for Google Compute Engine.
HOST = 'metadata'
PORT = 80

abbreviation :gce

# defaults
metadata_source 'metadata_sources/http_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

default_option([:metadata_source, :hosts], [:host => HOST, :port => PORT])

# root paths, don't leave off the trailing slashes
default_option([:cloud_metadata, :metadata_tree_climber, :root_path], '0.1/meta-data/')
default_option([:user_metadata, :metadata_tree_climber, :root_path], '0.1/meta-data/attributes/')

default_option([:cloud_metadata, :metadata_provider, :query_override], lambda do |provider, path|
  # auth token will return an error if we try to query
  result = provider.metadata_source.query(path)
  result = result.split("\n").select { |t| t !~ /auth.token/ }.join("\n")
  # filter out userdata for consitency with other clouds
  if path == provider.metadata_tree_climber.root_path
    result = result.split("\n").select { |t| t != 'attributes/' }.join("\n")
  end
  return result
end)

default_option([:user_metadata, :metadata_tree_climber, :has_children_override], lambda do |climber, path, query_result|
  # for ec2, metadata is a single value, for GCE, its a tree, override this
  # function so we'll recurse down
  return path =~ /\/$/
end)


# Determines if the current instance is running on GCE
#
# === Return
# true if running on GCE
def is_current_cloud?
  # See https://developers.google.com/compute/docs/instances#dmi
  `grep Google /sys/firmware/dmi/entries/1-0/raw 2>&1 >/dev/null`
  return $?.success?
end

# Provides details of the google cloud for inclusion in the cloud node.
#
# === Return
# always true
def update_details
  details = {}
  if ohai = @options[:ohai_node]
    # the 'network' key from cloud metadata contains a JSONized hash with the
    # public/private IP details.
    # example:
    #  ohai[:gce][:network] = "{\"networkInterface\":[{\"network\":\"projects/12345/networks/default\",\"ip\":\"10.11.12.13\",\"accessConfiguration\":[{\"type\":\"ONE_TO_ONE_NAT\",\"externalIp\":\"123.4.5.6\"}]}]}"
    public_ip = nil
    private_ip = nil
    if cloud_node = build_metadata(:cloud_metadata)
      begin
        network_json = cloud_node["network"]
        network_data = JSON.load(network_json)
        details[:network] = network_data
        if network_interface = network_data['networkInterface'] && network_data['networkInterface'].first
          private_ip = network_interface['ip']
          if access_configuration = network_interface['accessConfiguration'] && network_interface['accessConfiguration'].first
            public_ip = access_configuration['externalIp']
          end
        else
          logger.warn("No network interfaces found in #{self.name} network metadata")
        end
      rescue Exception => e
        logger.warn("Unable to parse #{self.name} network metadata from #{network_json.inspect}\n#{e.class}: #{e.message}")
      end
    end
    details[:public_ip] = public_ip if public_ip
    details[:private_ip] = private_ip if private_ip
  end
  return details
end
