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

    attr_accessor :uuid, :username, :public_key, :public_keys, :common_name, :superuser, :expires_at

    # Initialize fields from given arguments
    def initialize(*args)
      @uuid        = args[0]
      @username    = args[1]
      @public_key  = args[2]
      @common_name = args[3] || ''
      @superuser   = args[4] || false
      @expires_at  = Time.at(args[5]) if args[5] && (args[5] != 0) # nil -> 0 because of expires_at.to_i below
      @public_keys = args[6]

      # we now expect an array of public_keys to be passed while supporting the
      # singular public_key as a legacy member. when serialized back from a
      # legacy LoginUser record, the singular value may be set while the plural
      # is nil.
      if @public_keys
        raise ArgumentError, "Expected public_keys (seventh argument) to be an array" unless @public_keys.is_a?(Array)
        @public_key = @public_keys.first
      else
        raise ArgumentError, "Expected public_key (third argument) to be a string" unless @public_key.is_a?(String)
        @public_keys = [@public_key]
      end
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @uuid, @username, @public_key, @common_name, @superuser, @expires_at.to_i, @public_keys ]
    end

  end
end
