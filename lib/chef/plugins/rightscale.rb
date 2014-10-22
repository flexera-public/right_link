#
# Copyright (c) 2009-2011 RightScale Inc
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

# = NOTICE
# This plugin is deprecated!
#
# This is an ohai plugin that checks the state of the instance to
# determine if the RightScale plaform is available and add RightScale
# configuration data to the chef node.  This is the old way of doing things.
#
# Going forward we are passing in all RightScale configuration data via
# attributes called 'core-defined inputs'.  You can read more on the wiki:
# http://rightscale.onconfluence.com/display/rightscale/Cloud+Independent+Attributes
#
# This plugin remains until all configuration data is migrated from user-data to
# core-defined inputs.

require 'json'
 

Ohai.plugin(:RightScale) do
  provides "rightscale"

  META_DATA_FILE = "/var/spool/rackspace/user-data.txt"

  # Adds RightScale server FQDNs to the rightscale_deprecated servers Mash
  #
  # NOTE: This is a hack to convert the RS_(server) tokens into something more
  # intuative.  Hopefully this will be removed when we stop using EC2
  # userdata.
  #
  # === Parameters
  # key(String):: RightScale server token from user-data
  # data(String)::: FQDN for the RightScale server
  def add_server(key, data)
    rightscale_deprecated[:server] = Mash.new unless rightscale_deprecated.has_key?(:server)
    server_names = {
      "RS_sketchy" => "sketchy",
      "RS_syslog" => "syslog",
      "RS_lumberjack" => "lumberjack",
      "RS_server" => "core"
    }
    rightscale_deprecated[:server][server_names[key]] = data unless (server_names[key] == nil)
  end

  # ----------------------------------------
  # cloud
  # ----------------------------------------
  depends "cloud"

  # Detect if RightScale platform is running on ec2 cloud
  #
  # === Returns
  # true:: If ec2 Mash exists amd RightScale tokens found in user-data
  # false:: Otherwise
  def on_rightscale_ec2_platform?
    return false if (ec2 == nil || ec2[:userdata].match(/RS_/) == nil) # only ec2 supported
    true
  end

  # add all 'RS_' tokens in userdata, but perform translation for server names
  def get_data_from_ec2_user_date
    data_array = ec2[:userdata].split('&')
    data_array.each do |d|
      key, data = d.split('=')
      rightscale_deprecated[key.sub(/RS_/,'')] = data unless add_server(key,data)
    end
  end



  # ----------------------------------------
  # generic cloud
  # ----------------------------------------

  # Detect if RightScale platform is running on other cloud.
  # currently only rackspace is supported.
  #
  # === Returns
  # true:: If ec2 Mash exists amd RightScale tokens found in user-data
  # false:: Otherwise
  def on_rightscale_platform?
    File.exists?(META_DATA_FILE)
  end

  # add all 'RS_' tokens in medadata file, but perform translation for server names
  def get_data
    data_array = File.open(META_DATA_FILE)
    data_array.each do |d|
      key, data = d.split('=')
      key.strip!
      data.strip!
      rightscale_deprecated[key.sub(/RS_/,'')] = data unless add_server(key,data)
    end
  end

  collect_data do
    if on_rightscale_ec2_platform?
      rightscale_deprecated Mash.new
      get_data_from_ec2_user_date
    end
    # Adds rightscale_deprecated from metadata file, if available
    if on_rightscale_platform?
      rightscale_deprecated Mash.new
      get_data
    end
  end
end
