#
# Copyright (c) 2009-2011 RightScale Inc
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
  
  # RightScript with parameters and attachments
  class RightScriptInstantiation

    include Serializable  

    # (String) RightScript name
    attr_accessor :nickname

    # (String) RightScript source
    attr_accessor :source

    # (Hash) RightScript parameters
    # Hash of parameters names with associated value
    attr_accessor :parameters  
    
    # (Array) RightScript attachments URLs, array of RightScriptAttachment
    attr_accessor :attachments
    
    # (Array) RightScripts required packages
    attr_accessor :packages

    # (Integer) RightScript id
    attr_accessor :id

    # (Boolean) Whether script inputs are ready
    attr_accessor :ready

    # (Array of SecureDocumentLocation) attributes that must be resolved by the instance
    attr_accessor :external_inputs

    def initialize(*args)
      @nickname        = args[0] if args.size > 0
      @source          = args[1] if args.size > 1
      @parameters      = args[2] if args.size > 2
      @attachments     = args[3] if args.size > 3
      @packages        = args[4] if args.size > 4
      @id              = args[5] if args.size > 5
      @ready           = args[6] if args.size > 6
      @external_inputs = args[7] if args.size > 7
    end
    
    # Array of serialized fields given to constructor
    def serialized_members
      [ @nickname, @source, @parameters, @attachments, @packages, @id, @ready, @external_inputs ]
    end
    
  end
end
