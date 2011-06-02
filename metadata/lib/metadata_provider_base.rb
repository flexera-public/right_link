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

  # Base implementation for a metadata provider which implements recursive tree
  # building and relies on an external fetcher object
  class MetadataProviderBase < MetadataProvider

    def initialize(options)
      raise ArgumentError.new("options[:metadata_source] is required") unless @metadata_source = options[:metadata_source]
      @options = options
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
    def cloud_metadata
      return nil unless path = @options[:cloud_metadata_root_path]
      return nil unless @tree_climber = @options[:cloud_metadata_tree_climber]
      build_metadata(path)
    ensure
      @tree_climber = nil
    end

    # Queries cloud-agnostic instance metadata in an implementation-specific
    # manner. The resulting tree of metadata is built using the given Hash-like
    # class.
    #
    # === Return
    # tree_metadata(Hash|String):: tree of metadata or leaf value or nil
    #  depending on options
    #
    # === Raises
    # RightScale::MetadataSource::QueryFailed:: on failure to query metadata
    def user_metadata
      return nil unless path = @options[:user_metadata_root_path]
      return nil unless @tree_climber = @options[:user_metadata_tree_climber]
      build_metadata(path)
    ensure
      @tree_climber = nil
    end

    # Releases any resources used to get metadata. Must be called before
    # releasing provider.
    def finish
      @metadata_source.finish
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
    def build_metadata(path)
      query_result = @metadata_source.query(path)
      if @tree_climber.has_children?(path, query_result)
        metadata = @tree_climber.create_branch
        child_names = @tree_climber.child_names(path, query_result)
        child_names.each do |child_name|
          if key = @tree_climber.branch_key(child_name)
            branch_path = @metadata_source.append_branch_name(path, child_name)
            metadata[key] = build_metadata(branch_path)
          elsif key = @tree_climber.leaf_key(child_name)
            leaf_path = @metadata_source.append_leaf_name(path, child_name)
            metadata[key] = @tree_climber.create_leaf(leaf_path, @metadata_source.query(leaf_path))
          end
        end
        return metadata
      end

      # operate on only leaf.
      return @tree_climber.create_leaf(path, query_result)
    end

  end

end
