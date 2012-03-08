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

# dependencies.
metadata_source 'metadata_sources/file_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# set abbreviation for non-RS env var generation
abbreviation :rax

# Parses rackspace user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  ::RightScale::CloudUtilities.split_metadata(data.strip, "\n", result)
  result
end

# defaults.
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
default_option([:metadata_source, :user_metadata_source_file_path], File.join(RightScale::AgentConfig.cloud_state_dir, name.to_s, 'user-data.txt'))

# Determines if the current instance is running on rackspace.
#
# === Return
# true if running on rackspace
def is_current_cloud?
  if ohai = @options[:ohai_node]
    return true if ::RightScale::CloudUtilities.has_mac?(ohai, "00:00:0c:07:ac:01")
    return ohai[:kernel] && ohai[:kernel][:release].to_s.split('-').last.eql?("rscloud")
  end
  false
end

# Updates the given node with cloudstack details.
#
# === Return
# always true
def update_details
  details = {}
  if ohai = @options[:ohai_node]
    if platform.windows?
      details[:public_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'public')
      details[:private_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'private')
    else
      details[:public_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth0)
      details[:private_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth1)
    end
  end
  return details
end
