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

  # Simple certificate store, serves a static set of certificates
  class StaticCertificateStore
    
    # Initialize store
    #
    # === Parameters
    # signer_certs(Array|Certificate):: Signer certificate(s) used when loading data to
    #   check the digital signature. The signature associated with the serialized data
    #   needs to match with one of the signer certificates for loading to succeed.
    # recipients_certs(Array|Certificate):: Recipient certificate(s) used when serializing
    #   data for encryption. Loading the data can only be done through serializers that
    #   have been initialized with a certificate that's in the recipient certificates
    #   if encryption is enabled.
    def initialize(signer_certs, recipients_certs)
      signer_certs = [ signer_certs ] unless signer_certs.respond_to?(:each)
      @signer_certs = signer_certs 
      recipients_certs = [ recipients_certs ] unless recipients_certs.respond_to?(:each)
      @recipients_certs = recipients_certs
    end
    
    # Retrieve signer certificates
    #
    # === Parameters
    # id(String):: Serialized identity of signer, ignored
    #
    # === Return
    # (Array):: Signer certificates
    def get_signer(id)
      @signer_certs
    end

    # Retrieve recipient certificates that will be able to decrypt the serialized data
    #
    # === Parameters
    # packet(RightScale::Packet):: Packet containing recipient identity, ignored
    #
    # === Return
    # (Array):: Recipient certificates
    def get_recipients(packet)
      @recipients_certs
    end
    
  end # StaticCertificateStore

end # RightScale
