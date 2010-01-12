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

module RightScale

  # This class is used to interface the nanite mapper with an external security
  # module.
  # There are two points of integration:
  #  1. When an agent registers with a mapper
  #  2. When an agent sends a request to another agent 
  #
  # In both these cases the security module is called back and can deny the 
  # operation.
  # Note: it's the responsability of the module to do any logging or
  # notification that is required.
  class SecurityProvider
    
    # Register an external security module
    # This module should expose the 'authorize_registration' and 
    # 'authorize_request' methods.
    def self.register(mod)
      @security_module = mod
    end
    
    # Used internally by nanite to retrieve the current security module
    def self.get
      @security_module || default_security_module
    end
    
    # Default security module, authorizes all operations
    def self.default_security_module
      @default_sec_mod ||= DefaultSecurityModule.new
    end
    
  end
  
  # Default security module
  class DefaultSecurityModule
    
    # Authorize registration of agent (registration is an instance of RegisterPacket)
    def authorize_registration(registration)
      true
    end
    
    # Authorize given inter-agent request (request is an instance of RequestPacket)
    def authorize_request(request)
      true
    end
    
  end

end