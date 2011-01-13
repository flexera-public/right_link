#
# Copyright (c) 2009 RightScale Inc
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
#

module RightScale

  # Recipe with json
  class RecipeInstantiation

    include Serializable

    # (String) Recipe nickname
    attr_accessor :nickname

    # (Hash) Recipe override attributes (JSON string for RightLink v5.0)
    attr_accessor :attributes

    # (Integer) Recipe id
    attr_accessor :id

    # (Boolean) Whether recipe inputs are ready
    attr_accessor :ready

    def initialize(*args)
      @nickname   = args[0] if args.size > 0
      @attributes = args[1] if args.size > 1
      @id         = args[2] if args.size > 2
      @ready      = args[3] if args.size > 3
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @nickname, @attributes, @id, @ready ]
    end

  end
end
