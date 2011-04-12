rackspace[:public_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(self, 'public')
rackspace[:private_ip] =::RightScale::CloudUtilities.ip_for_windows_interface(self, 'private')
