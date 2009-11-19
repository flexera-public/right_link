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

  # Authorized user for the Managed Login feature
  class LoginUser
    include Serializable

    attr_accessor :uuid, :username, :public_key, :common_name, :superuser, :expires_at

    # Initialize fields from given arguments
    def initialize(*args)
      @uuid        = args[0]
      @username    = args[1]
      @public_key  = args[2]
      @common_name = args[3] || ''
      @superuser   = args[4] || false
      @expires_at  = args[5] ? Time.at(args[5]) : nil
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @uuid, @username, @public_key, @common_name, @superuser, @expires_at.to_i ]
    end

  end
end
