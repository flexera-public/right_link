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
  class AgentIdentityToken
    # Separator used to differentiate between identity components when serialized
    ID_SEPARATOR = '*'
    
    def self.derive(base_id, auth_token)
      sha = OpenSSL::Digest::SHA1.new
      sha.update(base_id.to_s)
      sha.update(ID_SEPARATOR)
      sha.update(auth_token.to_s)
      return sha.hexdigest
    end

    def self.create_verifier(base_id, auth_token, timestamp)
      hmac =  OpenSSL::HMAC.new(auth_token, OpenSSL::Digest::SHA1.new)
      hmac.update(base_id.to_s)
      hmac.update(ID_SEPARATOR)
      hmac.update(timestamp.to_s)
      return hmac.hexdigest
    end
  end
end