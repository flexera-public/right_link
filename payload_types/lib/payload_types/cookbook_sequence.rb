#--
# Copyright: Copyright (c) 2010 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

module RightScale
  # Sequence of cookbooks and where to put them.
  class CookbookSequence
    include Serializable

    # (Array) relative cookbook paths to use from the repository root.
    attr_accessor :paths
    # (Array) CookbookPosition objects for each cookbook.
    attr_accessor :positions

    # Initialize fields from given arguments
    def initialize(*args)
      @paths     = args[0]
      @positions = args[1] if args.size > 1
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @paths, @positions ]
    end

    # Reorder @positions so it respects @path.  The comparison rule is
    # as follows:
    # - for two pairs of cookbooks [a_pos, a_cookbook], [b_pos, b_cookbook]
    #  - let a_index be the index of the first element of cookbooks_path that is a prefix for a_pos.
    #  - let b_index be similarly defined on b_pos.
    #  - if a_index != b_index, sort on a_index and b_index.
    #  - otherwise lexically sort on a_pos and b_pos.
    def sort_by_path!
      indices = @positions.map {|a|
        @paths.index(@paths.find {|p| a.position.start_with? p})
      }
      @positions = indices.zip(@positions).sort {|a, b|
        aindex, acb = a
        bindex, bcb = b
        if aindex == bindex
          acb.position <=> bcb.position
        else
          aindex <=> bindex
        end
      }.map {|p| p.last}
    end
  end
end
