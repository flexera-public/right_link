#
# Copyright (c) 2010-2011 RightScale Inc
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


# Extends ohai/plugin/cloud with additional clouds
# that RightLink knows about
# Later this code will be contributed into

require_plugin 'cloud'
require_plugin 'cloudstack'
require_plugin 'softlayer'
require_plugin 'vscale'


# ----------------------------------------
#  cloudstack
# ----------------------------------------
#
# Is current cloud cloudstack?
#
# === Return
# true:: If cloudstack Hash is defined
# false:: Otherwise
def on_cloudstack?
  cloudstack != nil
end

# Fill cloud hash with cloudstack values
def get_cloudstack_values
  cloud[:public_ipv4] = cloudstack['public_ipv4']
  cloud[:public_ips] << cloudstack['public_ipv4'] if cloudstack['public_ipv4']
  cloud[:local_ipv4] = cloudstack['local_ipv4']
  cloud[:private_ips] << cloudstack['local_ipv4'] if cloudstack['local_ipv4']
  cloud[:public_hostname] = cloudstack['public_hostname']
  cloud[:local_hostname] = cloudstack['local_hostname']
  cloud[:provider] = 'cloudstack'
end

# Setup cloudstack cloud data
if on_cloudstack?
  create_objects
  get_cloudstack_values
end

def on_softlayer?
  softlayer != nil
end

def get_softlayer_values
  cloud[:public_ipv4] = softlayer['public_ipv4']
  cloud[:local_ipv4] = softlayer['local_ipv4']
  cloud[:public_ips].concat(softlayer['public_ips'])
  cloud[:private_ips].concat(softlayer['private_ips'])
  cloud[:provider] = 'softlayer'
end

if on_softlayer?
  create_objects
  get_softlayer_values
end

def on_vscale?
  vscale != nil
end

def get_vscale_values
  cloud[:public_ipv4] = vscale['public_ipv4']
  cloud[:local_ipv4] = vscale['local_ipv4']
  cloud[:public_ips].concat(vscale['public_ips'])
  cloud[:private_ips].concat(vscale['private_ips'])
  cloud[:provider] = 'vscale'
end

if on_vscale?
  create_objects
  get_vscale_values
end
