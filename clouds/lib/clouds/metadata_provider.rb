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

require File.normalize_path(File.join(File.dirname(__FILE__), 'metadata_provider'))

module RightScale

  # Abstracts a metadata provider which implements recursive tree building and
  # relies on an external fetcher object
  class MetadataProvider

    attr_accessor :metadata_source, :metadata_tree_climber, :raw_metadata_writer

    def initialize(options = {})
      @metadata_source = options[:metadata_source]
      @metadata_tree_climber = options[:metadata_tree_climber]
      @raw_metadata_writer = options[:raw_metadata_writer]
      @build_metadata_override = options[:build_metadata_override]
    end

    # Queries cloud-specific instance metadata in an implementation-specific
    # manner. The resulting tree of metadata is built using the given Hash-like
    # class.
    #
    # === Return
    # tree_metadata(Hash|String):: tree of metadata or leaf value or nil
    #  depending on options
    #
    # === Raises
    # RightScale::MetadataSource::QueryFailed:: on failure to query metadata
    def build_metadata
      return @build_metadata_override.call(self) if @build_metadata_override
      @root_path = @metadata_tree_climber.root_path
      recursive_build_metadata(@root_path)
    ensure
      @root_path = nil
    end

    protected

    # Queries the given path for metadata using the responder. The metadata is
    # then (recursively) processed according to the tree surgeon's analysis and
    # the metadata tree (or else flat data) is filled and returned.
    #
    # === Parameters
    # path(String):: path to metadata
    #
    # === Return
    # tree_metadata(Hash|String):: tree of metadata or raw value depending on
    #  options
    def recursive_build_metadata(path)
      # query
      query_result = @metadata_source.query(path)

      # climb, if arboreal
      if @metadata_tree_climber.has_children?(path, query_result)
        metadata = @metadata_tree_climber.create_branch
        child_names = @metadata_tree_climber.child_names(path, query_result)
        child_names.each do |child_name|
          if key = @metadata_tree_climber.branch_key(child_name)
            branch_path = @metadata_source.append_branch_name(path, child_name)
            metadata[key] = recursive_build_metadata(branch_path)
          elsif key = @metadata_tree_climber.leaf_key(child_name)
            leaf_path = @metadata_source.append_leaf_name(path, child_name)
            query_result = @metadata_source.query(leaf_path)
            write_raw_leaf_query_result(leaf_path, query_result)
            metadata[key] = @metadata_tree_climber.create_leaf(leaf_path, query_result)
          end
        end
        return metadata
      end

      # the only leaf.
      write_raw_leaf_query_result(path, query_result)
      return @metadata_tree_climber.create_leaf(path, query_result)
    end

    # Writes raw responses to query writer, if given
    #
    # === Parameters
    # path(String):: path to metadata
    # query_result(String):: raw query result
    #
    # === Return
    # always true
    def write_raw_leaf_query_result(path, query_result)
      if @raw_metadata_writer
        subpath = (path.length > @root_path.length) ? path[@root_path.length..-1] : nil
        @raw_metadata_writer.write(query_result, subpath)
      end
      true
    end

  end

end
