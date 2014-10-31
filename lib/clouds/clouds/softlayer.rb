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

CONFIG_DRIVE_MOUNTPOINT = File.join(RightScale::Platform.filesystem.spool_dir, name.to_s) if ::RightScale::Platform.linux?
CONFIG_DRIVE_MOUNTPOINT = File.join(ENV['ProgramW6432'], 'RightScale', 'Mount', 'Softlayer').gsub('/', '\\') if ::RightScale::Platform.windows?

# dependencies.
metadata_source 'metadata_sources/http_metadata_source'
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
  ::RightScale::CloudUtilities.split_metadata(data.strip, '&', result)
  result
end

# defaults.
default_option([:metadata_source, :hosts], [:host => 'api.service.softlayer.com', :port => 443])
default_option([:user_metadata, :metadata_tree_climber, :root_path], 'rest/v3/SoftLayer_Resource_Metadata/UserMetadata.txt')
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))
default_option([:cloud_metadata, :metadata_provider, :build_metadata_override], lambda { |*| {} })