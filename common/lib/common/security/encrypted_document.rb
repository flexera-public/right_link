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

  # Represents a signed an encrypted document that can be later decrypted using
  # the right private key and whose signature can be verified using the right
  # cert.
  # This class can be used both to encrypt and sign data and to then check the
  # signature and decrypt an encrypted document.
  class EncryptedDocument
  
    # Encrypt and sign data using certificate and key pair
    #
    # === Parameters
    # data(String):: Data to be encrypted
    # certs(Array):: Recipient certificates (certificates corresponding to private
    #   keys that may be used to decrypt data)
    # cipher(Cipher):: Cipher used for encryption, AES 256 CBC by default
    def initialize(data, certs, cipher = 'AES-256-CBC')
      cipher = OpenSSL::Cipher::Cipher.new(cipher)
      certs = [ certs ] unless certs.respond_to?(:collect)
      raw_certs = certs.collect { |c| c.raw_cert }
      @pkcs7 = OpenSSL::PKCS7.encrypt(raw_certs, data, cipher, OpenSSL::PKCS7::BINARY)
    end

    # Initialize from encrypted data
    #
    # === Parameters
    # encrypted_data(String):: Encrypted data
    #
    # === Return
    # doc(EncryptedDocument):: Encrypted document
    def self.from_data(encrypted_data)
      doc = EncryptedDocument.allocate
      doc.instance_variable_set(:@pkcs7, RightScale::PKCS7.new(encrypted_data))
      doc
    end
    
    # Encrypted data using DER format
    #
    # === Return
    # (String):: Encrypted data
    def encrypted_data
      @pkcs7.to_pem
    end
    
    # Decrypted data
    #
    # === Parameters
    # key(RsaKeyPair):: Key pair used for decryption
    # cert(Certificate):: Certificate to use for decryption
    #
    # === Return
    # (String):: Decrypted data
    def decrypted_data(key, cert)
      @pkcs7.decrypt(key.raw_key, cert.raw_cert)
    end

  end # EncryptedDocument

end # RightScale
