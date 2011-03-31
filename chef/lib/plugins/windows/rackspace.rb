  rackspace[:public_ip] = ::RightScale::CloudUtilities.ip_for_interface(self, "0x3")
  rackspace[:private_ip] = ::RightScale::CloudUtilities.ip_for_interface(self, "0x2")
