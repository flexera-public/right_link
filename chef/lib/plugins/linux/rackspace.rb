rackspace[:public_ip] = ::RightScale::CloudUtilities.ip_for_interface(self, :eth0)
rackspace[:private_ip] = ::RightScale::CloudUtilities.ip_for_interface(self, :eth1)
