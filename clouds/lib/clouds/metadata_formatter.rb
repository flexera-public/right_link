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

module RightScale

  # Abstracts a formatter which maps one kind of metadata output to another.
  class MetadataFormatter

    # RS_ is reserved for use by RightScale and should be avoided by users
    # passing non-RightScale metadata to instances.
    RS_METADATA_PREFIX = 'RS_'

    attr_accessor :formatted_path_prefix, :format_metadata_override

    # Initializer.
    #
    # === Parameters
    # options[:format_metadata_callback](Proc):: specialization callback or nil
    def initialize(options)
      # options
      @formatted_path_prefix = options[:formatted_path_prefix] || RS_METADATA_PREFIX

      # overrides
      @format_metadata_override = options[:format_metadata_override]
    end

    # Formats metadata such that any hierarchical details flattened into simple
    # key names.
    #
    # === Parameters
    # tree_metadata(Hash):: tree of raw metadata
    #
    # === Returns
    # flat_metadata(Hash):: flattened metadata
    def format_metadata(metadata)
      return @format_metadata_override.call(metadata) if @format_metadata_override
      return recursive_flatten_metadata(metadata)
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
      flat_path = metadata_path.join('_').gsub(/[\W,\/]/, '_').upcase
      if @formatted_path_prefix && !(flat_path.start_with?(RS_METADATA_PREFIX) || flat_path.start_with?(@formatted_path_prefix))
        return @formatted_path_prefix + flat_path
      end
      return flat_path
    end

  end  # MetadataFormatter

end  # RightScale
