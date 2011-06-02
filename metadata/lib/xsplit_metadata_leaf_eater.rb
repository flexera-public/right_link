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

require File.normalize_path(File.join(File.dirname(__FILE__), 'metadata_leaf_eater'))

module RightScale

  # Provides rules for splitting leaves into arrays.
  class XSplitMetadataLeafEater < MetadataLeafEater

    # Initializer.
    #
    # === Parameters
    # options[:leaf_split_character](Class):: character used to split values into arrays (defaults to newline)
    def initialize(options = {})
      @leaf_split_character = options[:leaf_split_character] || "\n"
    end

    # Splits leaf data into arrays of text using the initialized
    # :leaf_split_character option.
    #
    # === Parameters
    # path(String):: path to metadata
    # data(String):: raw data for leaf
    #
    # returns(Object):: any kind of leaf value
    def leaf_from(path, data)
      values = data.strip.gsub("\r\n", "\n").split(@leaf_split_character)
      return "" if values.empty?
      return (1 == values.size) ? values.first : values
    end

  end

end
