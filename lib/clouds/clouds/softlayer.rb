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

CONFIG_DRIVE_MOUNTPOINT = ::RightScale::Platform.windows? ? 'Z' : File.join(RightScale::AgentConfig.cloud_state_dir, name.to_s)

# dependencies.
metadata_source 'metadata_sources/config_drive_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

abbreviation :sl

# Parses softlayer user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  # REVIEW: This can (and will) raise an exception if the data is malformed or empty. I was putting it in a
  # begin/rescue/end block, but there doesn't appear to be a logger in scope to report the problem and exit gracefully.
  #
  # Also, is it appropriate to be parsing JSON here? Is a specific tree_climber for json more appropriate?
  #
  # REVIEWER:
  # (1) added an in-scope logger (it was always available as option(:logger)) for RightLink v5.8+
  # (2) catching and logging an exception here is reasonable; added it.
  # (3) as far as subclassing goes, the cloud definition methodology allows for overriding a few
  # methods in the existing code base instead of having to create a custom class hierarchy for each
  # cloud. either approach is supported, but the override philosophy used here seems simpler
  # (especially for new cloud providers who haven't seen much ruby up till now).
  parsed_data = nil
  begin
    parsed_data = JSON.parse(data.strip)
  rescue Exception => e
    logger.error("#{e.class}: #{e.message}")
  end
  ::RightScale::CloudUtilities.split_metadata(parsed_data[0], '&', result) unless !parsed_data || parsed_data.length == 0
  result
end

# defaults.
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
default_option([:metadata_source, :user_metadata_source_file_path], File.join(CONFIG_DRIVE_MOUNTPOINT, 'meta.js'))

default_option([:metadata_source, :config_drive_uuid], "681B-8C5D")
default_option([:metadata_source, :config_drive_filesystem], "vfat")
default_option([:metadata_source, :config_drive_label], 'METADATA')
default_option([:metadata_source, :config_drive_mountpoint],  CONFIG_DRIVE_MOUNTPOINT)

# Updates the given node with cloud metadata details.
#
# === Return
# always true
def update_details
  details = {}
  if ohai = @options[:ohai_node]
    if platform.windows?
      # TODO: Solve for windows, this is directly from the Rackspace cloud definition and may (probably will) be different in SL
      #details[:public_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'public')
      #details[:private_ip] = ::RightScale::CloudUtilities.ip_for_windows_interface(ohai, 'private')
    else
      details[:public_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth1)
      details[:private_ip] = ::RightScale::CloudUtilities.ip_for_interface(ohai, :eth0)
    end
  end
  return details
end