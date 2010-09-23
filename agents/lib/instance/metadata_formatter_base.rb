#
# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'metadata_formatter'))

module RightScale

  # Partial implementation of MetadataFormatter.
  class MetadataFormatterBase < MetadataFormatter

    # Formats metadata in an implementation-specific manner as a hash of
    # metadata with any hierarchical details flattened into simple key names.
    #
    # === Parameters
    # tree_metadata(Hash):: tree of raw metadata
    #
    # === Returns
    # flat_metadata(Hash):: flattened metadata
    def format_metadata(tree_metadata)
      return recursive_flatten_metadata(tree_metadata)
    end

    protected

    # Recursively flattens metadata.
    #
    # === Parameters
    # tree_metadata(Hash):: metadata to flatten
    # flat_metadata(Hash):: flattened metadata or {}
    # metadata_path(Array):: array of metadata path elements or []
    # path_index(int):: path array index to update or 0
    #
    # === Returns
    # flat_metadata(Hash):: flattened metadata
    def recursive_flatten_metadata(tree_metadata, flat_metadata = {}, metadata_path = [], path_index = 0)
      unless tree_metadata.empty?
        tree_metadata.each do |key, value|
          metadata_path[path_index] = key
          if value.respond_to?(:has_key?)
            recursive_flatten_metadata(value, flat_metadata, metadata_path, path_index + 1)
          else
            flat_path = flatten_metadata_path(metadata_path)
            flat_metadata[flat_path] = value
          end
        end
        metadata_path.pop
        raise "Unexpected path" unless metadata_path.size == path_index
      end
      return flat_metadata
    end

    # Flattens a sequence of metadata keys into a simple key string
    # distinguishing the path to a value stored at some depth in a tree of
    # metadata.
    #
    # === Parameters
    # metadata_path(Array):: array of metadata path elements
    #
    # === Returns
    # flat_path(String):: flattened path
    def flatten_metadata_path(metadata_path)
      return metadata_path.join('_').gsub(/[\W,\/]/, '_').upcase
    end

  end

end
