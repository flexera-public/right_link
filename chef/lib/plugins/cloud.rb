#
# Copyright (c) 2009 RightScale Inc
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

provides "cloud"

require_plugin "ec2"
require_plugin "rackspace"

# Make top-level cloud hashes
#
def create_hashes
  cloud Mash.new
  cloud[:public_ip] = Hash.new
  cloud[:private_ip] = Hash.new
end

# ----------------------------------------
# ec2
# ----------------------------------------

# Is current cloud ec2?
#
# === Return
# true:: If ec2 Hash is defined
# false:: Otherwise
def on_ec2?
  ec2 != nil
end

# Fill cloud hash with ec2 values
def get_ec2_values 
  cloud[:public_ip][0] = ec2['public_ipv4']
  cloud[:private_ip][0] = ec2['local_ipv4']
  cloud[:provider] = "ec2"
end

# setup ec2 cloud  
if on_ec2?
  create_hashes
  get_ec2_values
end

# ----------------------------------------
# rackspace
# ----------------------------------------

# Is current cloud rackspace?
#
# === Return
# true:: If rackspace Hash is defined
# false:: Otherwise
def on_rackspace?
  rackspace != nil
end

# Fill cloud hash with rackspace values
def get_rackspace_values
  cloud[:public_ip][0] = rackspace['public_ip']
  cloud[:private_ip][0] = rackspace['private_ip']
  cloud[:provider] = "rackspace"
end

# setup rackspace cloud 
if on_rackspace?
  create_hashes
  get_rackspace_values
end
