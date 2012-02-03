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

# host/port are constants for EC2.
HOST = '169.254.169.254'
PORT = 80
SHEBANG_REGEX = /^#!/

# dependencies.
metadata_source 'metadata_sources/selective_metadata_source'
metadata_writers 'metadata_writers/dictionary_metadata_writer',
                 'metadata_writers/ruby_metadata_writer',
                 'metadata_writers/shell_metadata_writer'

# Assembles the command line needed to regenerate cloud metadata on demand.
def cloud_metadata_generation_command
  ruby_path = File.normalize_path(AgentConfig.sandbox_ruby_cmd)
  rs_cloud_path = File.normalize_path(File.join(AgentConfig.parent_dir, 'right_link', 'bin', 'cloud.rb'))
  return "#{ruby_path} #{rs_cloud_path} --quiet --action write_cloud_metadata"
end

# Selects metadata from multiple sources in support of serverizing existing
# long-running instances. Stops merging metadata as soon as RS_ variables
# are found.
def select_rs_metadata(_, path, metadata_source_type, query_result, previous_metadata)
  # note that clouds can extend this cloud and change the user root option.
  @cached_user_metadata_root_path = option([:user_metadata, :metadata_tree_climber, :root_path]) unless @cached_user_metadata_root_path
  query_next_metadata = false
  merged_metadata = query_result
  if path == @cached_user_metadata_root_path
    # metadata from file source is delimited by newline while metadata from http
    # is delimited by ampersand (unless shebang is present for legacy reasons).
    # convert ampersand-delimited to newline-delimited for easier comparison
    # with regular expression.
    previous_metadata.strip!
    query_result.strip!
    if (metadata_source_type == 'metadata_sources/file_metadata_source') || (query_result =~ SHEBANG_REGEX)
      current_metadata = query_result.gsub("\r\n", "\n").strip
    else
      current_metadata = query_result.gsub("&", "\n").strip
    end

    # will query next source only if current metadata does not contain RS_
    query_next_metadata = !(current_metadata =~ /^RS_rn_id/i)
    merged_metadata = (previous_metadata + "\n" + current_metadata).strip
    merged_metadata = merged_metadata.gsub("\n", "&") unless merged_metadata =~ SHEBANG_REGEX
  end
  return {:query_next_metadata => query_next_metadata, :merged_metadata => merged_metadata}
end

# Parses ec2 user metadata into a hash.
#
# === Parameters
# tree_climber(MetadataTreeClimber):: tree climber
# data(String):: raw data
#
# === Return
# result(Hash):: Hash-like leaf value
def create_user_metadata_leaf(tree_climber, data)
  result = tree_climber.create_branch
  data.strip!
  if data =~ SHEBANG_REGEX
    ::RightScale::CloudUtilities.split_metadata(data.gsub("\r\n", "\n"), "\n", result)
  else
    ::RightScale::CloudUtilities.split_metadata(data, '&', result)
  end
  result
end

# defaults
default_option([:metadata_source, :hosts], [:host => HOST, :port => PORT])
default_option([:metadata_source, :metadata_source_types], ['metadata_sources/http_metadata_source', 'metadata_sources/file_metadata_source'])
default_option([:metadata_source, :select_metadata_override], method(:select_rs_metadata))
default_option([:metadata_source, :user_metadata_source_file_path], File.join(RightScale::AgentConfig.cloud_state_dir, name.to_s, 'user-data.txt'))

default_option([:cloud_metadata, :metadata_tree_climber, :root_path], 'latest/meta-data')
default_option([:cloud_metadata, :metadata_writers, :ruby_metadata_writer, :generation_command], cloud_metadata_generation_command)

default_option([:user_metadata, :metadata_tree_climber, :root_path], 'latest/user-data')
default_option([:user_metadata, :metadata_tree_climber, :has_children_override], lambda{ false })
default_option([:user_metadata, :metadata_tree_climber, :create_leaf_override], method(:create_user_metadata_leaf))

# ensure file metadata source uses same root paths as http source.
default_option([:metadata_source, :cloud_metadata_root_path], option([:cloud_metadata, :metadata_tree_climber, :root_path]))
default_option([:metadata_source, :user_metadata_root_path], option([:user_metadata, :metadata_tree_climber, :root_path]))

# Determines if the current instance is running on the EC2.
#
# === Return
# true if running on EC2
def is_current_cloud?
  if ohai = @options[:ohai_node]
    if ::RightScale::CloudUtilities.has_mac?(ohai, "fe:ff:ff:ff:ff:ff")
      source = create_dependency_type(:user_metadata, :metadata_source)
      return ::RightScale::CloudUtilities.can_contact_metadata_server?(source.host, source.port)
    end
  end
  false
end
