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

if defined?(OpenSSL::PKCS7::PKCS7)
  RightScale::PKCS7 = OpenSSL::PKCS7::PKCS7
else
  RightScale::PKCS7 = OpenSSL::PKCS7
end

module RightScale

  # Signature that can be validated against certificates
  class Signature
    
    FLAGS = OpenSSL::PKCS7::NOCERTS || OpenSSL::PKCS7::BINARY || OpenSSL::PKCS7::NOATTR || OpenSSL::PKCS7::NOSMIMECAP || OpenSSL::PKCS7::DETACH

    # Create signature using certificate and key pair.
    #
    # Arguments:
    #  - 'data': Data to be signed
    #  - 'cert': Certificate used for signature
    #  - 'key':  RsaKeyPair used for signature
    #
    def initialize(data, cert, key)
      @p7 = OpenSSL::PKCS7.sign(cert.raw_cert, key.raw_key, data, [], FLAGS)
      @store = OpenSSL::X509::Store.new
    end
    
    # Load signature previously serialized via 'data'
    def self.from_data(data)
      sig = Signature.allocate
      sig.instance_variable_set(:@p7, RightScale::PKCS7.new(data))
      sig.instance_variable_set(:@store, OpenSSL::X509::Store.new)
      sig
    end

    # 'true' if signature was created using given cert, 'false' otherwise
    def match?(cert)
      @p7.verify([cert.raw_cert], @store, nil, OpenSSL::PKCS7::NOVERIFY)
    end

    # Signature in PEM format
    def data
      @p7.to_pem
    end
    alias :to_s :data

  end # Signature
  
end # RightScale
