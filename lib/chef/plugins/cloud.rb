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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'clouds', 'register_clouds'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'clouds'))

provides "cloud"

require_plugin "network"

begin
  # create the default cloud using ohai for detection, if necessary.
  cloud Mash.new
  cloud[:marker] = 'kruk'
  cloud[:public_ips] = Array.new
  cloud[:private_ips] = Array.new
  options = {:ohai_node => self}

  # ensure metadata tree(s) are built using Mash.
  options[:metadata_tree_climber] = {:tree_class => Mash}

  # ensure user metadata is returned in raw form for legacy node support.
  options[:user_metadata] = {:metadata_tree_climber => {:create_leaf_override => lambda { |_, value| value }}}

  # log to the ohai log
  options[:logger] = ::RightScale::Log

  # create the cloud instance
  cloud_instance = ::RightScale::CloudFactory.instance.create(::RightScale::CloudFactory::UNKNOWN_CLOUD_NAME, options)

  cloud[:provider] = cloud_instance.name

  cloud_node_update = Mash.new
  cloud_metadata = cloud_instance.build_metadata(:cloud_metadata)
  if cloud_metadata.kind_of?(::Hash)
    cloud_node_update.update(cloud_metadata)
  end

  # cloud may have specific details to insert into ohai node(s).
  cloud_node_update.update(cloud_instance.update_details)

  # expecting public/private IPs to come from all clouds (but only if they
  # support instance-facing APIs).
  public_ip4 = cloud_node_update[:"public-ipv4"] || cloud_node_update[:public_ipv4] || cloud_node_update[:public_ip]
  private_ip4 = cloud_node_update[:"local-ipv4"] || cloud_node_update[:local_ipv4] || cloud_node_update[:private_ip]

  # support the various cloud node keys found in ohai's cloud plugin.
  # note that we avoid setting the value if nil (because we have some workarounds
  # for clouds without instance-facing APIs).
  if public_ip4
    cloud[:public_ipv4] = public_ip4
    cloud[:public_ips] << public_ip4
  end
  if private_ip4
    cloud[:local_ipv4] = private_ip4
    cloud[:private_ips] << private_ip4
  end
  cloud[:public_hostname] = cloud_node_update['public_hostname']
  cloud[:local_hostname] = cloud_node_update['local_hostname']

rescue Exception => e
  # cloud was unresolvable, but not all ohai use cases are cloud instances.
  ::RightScale::Log.info(::RightScale::Log.format("Cloud was unresolvable", e, :caller))
  cloud nil
end
