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
#

module RightScale

  # Class encapsulating the actual value of a credential.
  class SecureDocument

    include Serializable

    # (String) Namespace-unique identifier for this credential value
    attr_accessor :name

    # (Integer) Monotonic version number of this document
    attr_accessor :version

    # The content of this document; if envelope_mime_type is not nil, then this value
    # is actually an envelope that contains the document value
    attr_accessor :content

    # (String) Name of the storage policy used to encrypt this document (if any).
    attr_accessor :storage_policy_name

    # (String) MIME type of the document itself e.g. "text/plain"
    attr_accessor :mime_type

    # (String) MIME type of the value's envelope, e.g. an encoding or encryption format,
    # or nil if there is no envelope MIME type.
    attr_accessor :envelope_mime_type

    # Initialize fields from given arguments
    def initialize(*args)
      @name                = args[0] if args.size > 0
      @version             = args[1] if args.size > 1
      @content             = args[2] if args.size > 2
      @storage_policy_name = args[3] if args.size > 3
      @mime_type           = args[4] if args.size > 4
      @envelope_mime_type  = args[5] if args.size > 5
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @name, @version, @content, @storage_policy_name, @mime_type, @envelope_mime_type ]
    end
  end
end
