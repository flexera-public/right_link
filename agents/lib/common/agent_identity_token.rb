# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.

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
  end
end