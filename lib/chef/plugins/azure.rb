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
DEFAULT_PUBLIC_SSH_PORT = 22
DEFAULT_PUBLIC_WINRM_PORT = 5985

require 'chef/ohai/mixin/rightlink'
require_plugin 'hostname'

def tcp_test_winrm(ip_addr, port, &block)
  socket = TCPSocket.new(hostname, port)
  ::Ohai::Log.debug("WinRM accepting connections on #{fqdn}")
  yield if block
  true
rescue SocketError
  sleep 2
  false
rescue Errno::ETIMEDOUT
  false
rescue Errno::EPERM
  false
rescue Errno::ECONNREFUSED
  sleep 2
  false
rescue Errno::EHOSTUNREACH
  sleep 2
  false
rescue Errno::ENETUNREACH
  sleep 2
  false
ensure
  socket && socket.close
end

def tcp_test_ssh(fqdn, sshport, &block)
  socket = TCPSocket.new(fqdn, sshport)
  readable = IO.select([socket], nil, nil, 5)
  if readable
    ::Ohai::Log.debug("sshd accepting connections on #{fqdn}, banner is #{socket.gets}")
    yield if block
    true
  else
    false
  end
rescue SocketError
  sleep 2
  false
rescue Errno::ETIMEDOUT
  false
rescue Errno::EPERM
  false
rescue Errno::ECONNREFUSED
  sleep 2
  false
rescue Errno::EHOSTUNREACH
  sleep 2
  false
ensure
  socket && socket.close
end

def looks_like_azure?
  looks_like_azure = hint?('azure')
  ::Ohai::Log.debug("looks_like_azure? == #{looks_like_azure.inspect}")
  looks_like_azure
end


if looks_like_azure?
  azure Mash.new
  azure['public_ip'] = ::Ohai::Mixin::RightLink::CloudUtilities.query_whats_my_ip(:logger=>::Ohai::Log)
  azure['vm_name'] = self['hostname'] if self['hostname']
  azure['public_fqdn'] = "#{self['hostname']}.cloudapp.net" if self['hostname']
  if azure['public_ip']
    tcp_test_ssh( azure['public_ip'], DEFAULT_PUBLIC_SSH_PORT) { azure['public_ssh_port'] = DEFAULT_PUBLIC_SSH_PORT }
    tcp_test_winrm(azure['public_ip'], DEFAULT_PUBLIC_WINRM_PORT) { azure['public_winrm_port'] = DEFAULT_PUBLIC_WINRM_PORT }
  end
end