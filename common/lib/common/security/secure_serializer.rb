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

    class MissingCertificate < Exception; end
    class InvalidSignature < Exception; end

    # Initialize serializer, must be called prior to using it
    #
    # === Parameters
    # serializer(Serializer):: Object serializer
    # identity(String):: Serialized identity associated with serialized messages
    # cert(String):: Certificate used to sign and decrypt serialized messages
    # key(RsaKeyPair):: Private key corresponding to specified cert
    # store(Object):: Certificate store exposing certificates used for
    #   encryption (get_recipients) and signature validation (get_signer)
    # encrypt(Boolean):: true if data should be signed and encrypted, otherwise
    #   just signed, true by default
    def self.init(serializer, identity, cert, key, store, encrypt = true)
      @identity = identity
      @cert = cert
      @key = key
      @store = store
      @encrypt = encrypt
      @serializer = serializer
    end
    
    # Was serializer initialized?
    def self.initialized?
      @identity && @cert && @key && @store
    end

    # Serialize, sign, and encrypt message
    # Sign and encrypt using X.509 certificate
    #
    # === Parameters
    # obj(Object):: Object to be serialized and encrypted
    # encrypt(Boolean|nil):: true if object should be signed and encrypted,
    #   false if just signed, nil means use class setting
    #
    # === Return
    # (String):: MessagePack serialized and optionally encrypted object
    #
    # === Raise
    # Exception:: If certificate identity, certificate store, certificate, or private key missing
    def self.dump(obj, encrypt = nil)
      raise "Missing certificate identity" unless @identity
      raise "Missing certificate" unless @cert
      raise "Missing certificate key" unless @key
      raise "Missing certificate store" unless @store || !@encrypt
      must_encrypt = encrypt.nil? ? @encrypt : encrypt
      serialize_format = if obj.respond_to?(:send_version) && obj.send_version >= 12
        @serializer.format
      else
        :json
      end
      encode_format = serialize_format == :json ? :pem : :der
      msg = @serializer.dump(obj, serialize_format)
      if must_encrypt
        certs = @store.get_recipients(obj)
        if certs
          msg = EncryptedDocument.new(msg, certs).encrypted_data(encode_format)
        else
          target = obj.target_for_encryption if obj.respond_to?(:target_for_encryption)
          RightLinkLog.warn("No certs available for object #{obj.class} being sent to #{target.inspect}\n") if target
        end
      end
      sig = Signature.new(msg, @cert, @key).data(encode_format)
      @serializer.dump({'id' => @identity, 'data' => msg, 'signature' => sig, 'encrypted' => !certs.nil?}, serialize_format)
    end
    
    # Decrypt, authorize signature, and unserialize message
    # Use x.509 certificate store for decrypting and validating signature
    #
    # === Parameters
    # msg(String):: Serialized and optionally encrypted object using MessagePack or JSON
    #
    # === Return
    # (Object):: Unserialized object
    #
    # === Raise
    # Exception:: If certificate store, certificate, or private key missing
    # MissingCertificate:: If could not find certificate for message signer
    # InvalidSignature:: If message signature check failed for message
    def self.load(msg)
      raise "Missing certificate store" unless @store
      raise "Missing certificate" unless @cert || !@encrypt
      raise "Missing certificate key" unless @key || !@encrypt

      msg = @serializer.load(msg)
      sig = Signature.from_data(msg['signature'])
      certs = @store.get_signer(msg['id'])
      raise MissingCertificate.new("Could not find a certificate for signer #{msg['id']}") unless certs

      certs = [ certs ] unless certs.respond_to?(:any?)
      raise InvalidSignature.new("Failed signature check for signer #{msg['id']}") unless certs.any? { |c| sig.match?(c) }

      data = msg['data']
      if data && @encrypt && msg['encrypted']
        data = EncryptedDocument.from_data(data).decrypted_data(@key, @cert)
      end
      @serializer.load(data) if data
    end

  end # SecureSerializer

end # RightScale
