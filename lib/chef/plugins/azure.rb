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

provides 'azure'
# DEFAULT_PUBLIC_SSH_PORT = 22
# DEFAULT_PUBLIC_WINRM_PORT = 5985

require 'chef/ohai/mixin/azure_metadata'

# require_plugin 'hostname'

extend ::Ohai::Mixin::AzureMetadata

@host = dhcp_lease_provider

def looks_like_azure?
  looks_like_azure = hint?('azure') && can_metadata_connect?(@host, 80)
  ::Ohai::Log.debug("looks_like_azure? == #{looks_like_azure.inspect}")
  looks_like_azure
end


if looks_like_azure? && (metadata = fetch_metadata(@host))
  azure Mash.new
  metadata.each { |k,v| azure[k] = v }

  # shared_config = SharedConfig.new rescue nil

  # if shared_config
  #   azure['public_ip'] = shared_config.public_ip
  #   azure['vm_name'] = shared_config.vm_name
  #   azure['public_fqdn'] = "#{shared_config.vm_name}.cloudapp.net"
  #   azure['public_ssh_port'] = shared_config.public_ssh_port
  # # else
  # #   azure['public_ip'] = query_whats_my_ip(:logger=>::Ohai::Log)
  # #   azure['vm_name'] = self['hostname'] if self['hostname']
  # #   azure['public_fqdn'] = "#{self['hostname']}.cloudapp.net" if self['hostname']
  # #   if azure['public_ip']
  # #     tcp_test_ssh( azure['public_ip'], DEFAULT_PUBLIC_SSH_PORT) { azure['public_ssh_port'] = DEFAULT_PUBLIC_SSH_PORT }
  # #     tcp_test_winrm(azure['public_ip'], DEFAULT_PUBLIC_WINRM_PORT) { azure['public_winrm_port'] = DEFAULT_PUBLIC_WINRM_PORT }
  # #   end
  # end

end
