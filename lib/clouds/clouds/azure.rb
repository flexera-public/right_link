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

# only Windows (2008 R2+) is known to be supported on WAZ (Linux on WAZ? no way!)
fail "Windows Azure cloud support is not implemented for this platform." unless platform.windows?

# dependencies.
metadata_source 'metadata_sources/certificate_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :waz

# Parses azure user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, '&', result)
  result
end

# defaults.
default_option([:metadata_source, :user_metadata_cert_store], "cert:/LocalMachine/My")
default_option([:metadata_source, :user_metadata_cert_issuer], "O=RightScale, C=US, S=CA, CN=RightScale User Data")

default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))

# Determines if the current instance is running on rackspace.
#
# === Return
# true if running on azure
def is_current_cloud?
  # FIX: the presence of the user data cert isn't sufficient criteria to
  # determine whether this is an azure instance. is there a mac address we can
  # check against? in the meantime, just say no.
  false
end

# Updates the given node with azure details.
#
# === Return
# always true
def update_details
  details = {}
  if ohai = @options[:ohai_node]
    details[:public_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'public')
    details[:private_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'private')
  end
  return details
end
