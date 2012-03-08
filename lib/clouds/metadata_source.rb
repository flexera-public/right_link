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

module RightScale

  # Interface for a metadata source.
  class MetadataSource

    # exceptions.
    class QueryFailed < Exception; end

    attr_reader :logger

    def initialize(options)
      raise ArgumentError, "options[:logger] is required" unless @logger = options[:logger]
    end

    # Appends a branch name to the given path.
    #
    # === Parameters
    # path(String):: metadata path
    # branch_name(String):: branch name to append
    #
    # === Return
    # result(String):: updated path
    def append_branch_name(path, branch_name)
      # remove anything after equals.
      branch_name = branch_name.gsub(/\=.*$/, '')
      branch_name = "#{branch_name}/" unless '/' == branch_name[-1..-1]
      return append_leaf_name(path, branch_name)
    end

    # Appends a leaf name to the given path.
    #
    # === Parameters
    # path(String):: metadata path
    # leaf_name(String):: leaf name to append
    #
    # === Return
    # result(String):: updated path
    def append_leaf_name(path, leaf_name)
      path = "#{path}/" unless '/' == path[-1..-1]
      return "#{path}#{URI.escape(leaf_name)}"
    end

    # Queries for metadata using the given path.
    #
    # === Parameters
    # path(String):: metadata path
    #
    # === Return
    # metadata(String):: query result or empty
    #
    # === Raises
    # QueryFailed:: on any failure to query
    def query(path)
      raise NotImplementedError
    end

    # Releases any resources used to query metadata. Must be called before
    # releasing source.
    def finish
      raise NotImplementedError
    end

  end

end
