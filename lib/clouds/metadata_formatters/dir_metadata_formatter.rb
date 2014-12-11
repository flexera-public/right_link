#
# Copyright (c) 2010-2011 RightScale Inc
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

require File.expand_path("../flat_metadata_formatter", __FILE__)

module RightScale

  class DirMetadataFormatter < FlatMetadataFormatter

    # Initializer.
    #
    # === Parameters
    # Don't use superclass initialize, it sets some options we don't want
    def initialize(options = {}); end

    # Formats a structured json blob such that sublevels in the structured json
    # get translated to slashes, as in a hierarhical file system. i.e.
    # { :a => { :b => "X", :c => "Y"}} would now be {"a/b" => "X", "a/c" => "Y"}
    #
    # === Parameters
    # metadata(Hash):: tree of raw metadata
    #
    # === Returns
    # flat_metadata(Hash):: flattened metadata (single level hash)
    def format(metadata)
      return recursive_flatten_metadata(metadata)
    end

    def can_format?(metadata)
      metadata.respond_to?(:has_key?)
    end

    protected

    def transform_path(path)
      path.join("/")
    end
  end
end  # RightScale
