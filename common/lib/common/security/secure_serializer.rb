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
  
  # Serializer implementation which secures messages by using
  # X.509 certificate signing
  class SecureSerializer

    # Initialize serializer, must be called prior to using it
    #
    # === Parameters
    #  identity(String):: Serialized identity associated with serialized messages
    #  cert(String):: Certificate used to sign and decrypt serialized messages
    #  key(RsaKeyPair):: Private key corresponding to specified cert
    #  store(Object):: Certificate store exposing certificates used for
    #    encryption (get_recipients) and signature validation (get_signer)
    #  encrypt(Boolean):: true if data should be signed and encrypted, otherwise
    #    just signed, true by default
    def self.init(identity, cert, key, store, encrypt = true)
      @identity = identity
      @cert = cert
      @key = key
      @store = store
      @encrypt = encrypt
    end
    
    # Was serializer initialized?
    def self.initialized?
      @identity && @cert && @key && @store
    end

    # Serialize message and sign it using X.509 certificate
    #
    # === Parameters
    # obj(Object):: Object to serialized and encrypted
    # encrypt(Boolean|nil):: true if object should be signed and encrypted,
    #   false if just signed, nil means use global setting
    #
    # === Return
    # (String):: JSON serialized and optionally encrypted object
    def self.dump(obj, encrypt = nil)
      raise "Missing certificate identity" unless @identity
      raise "Missing certificate" unless @cert
      raise "Missing certificate key" unless @key
      raise "Missing certificate store" unless @store || !@encrypt
      must_encrypt = encrypt.nil? ? @encrypt : encrypt
      json = obj.to_json
      if must_encrypt
        certs = @store.get_recipients(obj)
        if certs
          json = EncryptedDocument.new(json, certs).encrypted_data
        else
          target = obj.target_for_encryption if obj.respond_to?(:target_for_encryption)
          RightLinkLog.warn("No certs available for object #{obj.class} being sent to #{target.inspect}\n") if target
        end
      end
      sig = Signature.new(json, @cert, @key)
      {'id' => @identity, 'data' => json, 'signature' => sig.data, 'encrypted' => !certs.nil?}.to_json
    end
    
    # Unserialize data using certificate store
    #
    # === Parameters
    # json(String):: JSON serialized and optionally encrypted object
    #
    # === Return
    # (Object):: Unserialized object
    def self.load(json)
      raise "Missing certificate store" unless @store
      raise "Missing certificate" unless @cert || !@encrypt
      raise "Missing certificate key" unless @key || !@encrypt
      data = JSON.load(json)
      sig = Signature.from_data(data['signature'])
      certs = @store.get_signer(data['id'])
      raise "Could not find a cert for signer #{data['id']}" unless certs
      certs = [ certs ] unless certs.respond_to?(:any?)
      raise "Failed to check signature for signer #{data['id']}" unless certs.any? { |c| sig.match?(c) }
      jsn = data['data']
      if jsn && @encrypt && data['encrypted']
        jsn = EncryptedDocument.from_data(jsn).decrypted_data(@key, @cert)
      end
      JSON.load(jsn) if jsn
    end
       
  end # SecureSerializer

end # RightScale
