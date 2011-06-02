#
# Copyright (c) 2010-11 RightScale Inc
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

require File.normalize_path(File.join(File.dirname(__FILE__), 'metadata_tree_climber'))

module RightScale

  # Provides rules for building a standard metadata tree from raw data and
  # expanding multi-line leaf values into arrays. Details of querying raw
  # metadata are external to this class.
  class MetadataTreeClimber

    # Initializer.
    #
    # === Parameters
    # options[:tree_class](Class):: Hash-like class to use when building
    #  metadata tree (defaults to Hash)
    def initialize(options = {})
      # parameters
      @root_path = options[:root_path] || ''
      @tree_class = options[:tree_class] || Hash
      @child_name_delimiter = options[:child_name_delimiter] || "\n"

      # callbacks (optional)
      @branch_key_callback = options[:branch_key_callback]
      @child_names_callback = options[:child_names_callback]
      @has_children_callback = options[:has_children_callback]
      @leaf_key_callback = options[:leaf_key_callback]
      @leaf_value_callback = options[:leaf_value_callback]
    end

    # Determines if the given path represents a parent branch. This information
    # can be empirically determined from the path by the appearance of a
    # trailing forward slash using the HTTP convention (even if metadata source
    # is not an HTTP connection) except for the root which must be tested
    # specially.
    #
    # === Parameters
    # path(String):: path to metadata
    # values(String):: raw data queried using path
    #
    # === Return
    # result(Boolean):: true if branch, false if leaf
    def has_children?(path, values)
      return @has_children_callback.call(path, values) if @has_children_callback
      return '/' == path[-1..-1] || path == @root_path
    end

    # Determines if the given raw value contains branch/leaf names and returns
    # them as pair of Hash-like objects of keys with nil values.
    #
    # === Parameters
    # path(String):: path to metadata
    # query_result(String):: raw data queried using path
    #
    # === Returns
    # result(Array):: array of child (leaf or branch) names or empty
    def child_names(path, query_result)
      return @children_from_callback.call(path, query_result) if @children_from_callback
      child_names = []
      sub_values = query_result.gsub("\r\n", "\n").split(@child_name_delimiter)
      sub_values.each do |sub_value|
        sub_value.strip!
        (child_names << sub_value) unless sub_value.empty?
      end
      return child_names
    end

    # Creates a new empty tree node based on the class specified in options.
    #
    # === Returns
    # result(Hash):: new Hash-like node
    def create_branch
      @tree_class.new
    end

    # Creates a new leaf using the given information (from which leaf type can
    # be inferred, etc.).
    #
    # === Parameters
    # path(String):: path to metadata
    # value(String):: raw data queried using path
    #
    def create_leaf(path, value)
      return @leaf_value_callback.call(leaf_value) if @leaf_value_callback
      return value.strip
    end

    # Looks for equals anywhere in the sub-value or trailing forward slash at
    # the end of the sub-value.
    #
    # === Parameters
    # branch_name(String):: branch name
    #
    # === Returns
    # key(String):: branch key or nil
    def branch_key(branch_name)
      return @branch_key_callback.call(branch_name) if (branch_name && @branch_key_callback)

      # replace any equals and subsequent text with forward slash and chomp any
      # trailing slash. note that chomp! returns nil if character (i.e. slash)
      # is not found at end.
      return branch_name.gsub(/\=.*$/, '/').chomp!('/')
    end

    # Leaf name is used as key by default.
    #
    # === Parameters
    # leaf_name(String):: leaf name
    #
    # === Returns
    # key(String):: leaf key or nil
    def leaf_key(leaf_name)
      return @leaf_key_callback.call(branch_name) if @leaf_key_callback
      return leaf_name
    end

  end

end
