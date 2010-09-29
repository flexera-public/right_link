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

  # X.509 Certificate management
  class Certificate
    
    # Underlying OpenSSL cert
    attr_accessor :raw_cert
  
    # Generate a signed X.509 certificate
    #
    # === Parameters
    # key(RsaKeyPair):: Key pair used to sign certificate
    # issuer(DistinguishedName):: Certificate issuer
    # subject(DistinguishedName):: Certificate subject
    # valid_for(Integer):: Time in seconds before certificate expires, defaults to 10 years
    def initialize(key, issuer, subject, valid_for = 3600*24*365*10)
      @raw_cert = OpenSSL::X509::Certificate.new
      @raw_cert.version = 2
      @raw_cert.serial = 1
      @raw_cert.subject = subject.to_x509
      @raw_cert.issuer = issuer.to_x509
      @raw_cert.public_key = key.to_public.raw_key
      @raw_cert.not_before = Time.now
      @raw_cert.not_after = Time.now + valid_for
      @raw_cert.sign(key.raw_key, OpenSSL::Digest::SHA1.new)
    end
    
    # Load certificate from file
    #
    # === Parameters
    # file(String):: File path name
    #
    # === Return
    # res(Certificate):: Certificate
    def self.load(file)
      res = nil
      File.open(file, 'r') { |f| res = from_data(f) }
      res
    end
    
    # Initialize with raw certificate
    #
    # === Parameters
    # data(String):: Raw certificate data
    #
    # === Return
    # res(Certificate):: Certificate
    def self.from_data(data)
      cert = OpenSSL::X509::Certificate.new(data)
      res = Certificate.allocate
      res.instance_variable_set(:@raw_cert, cert)
      res
    end
    
    # Save certificate to file in PEM format
    #
    # === Parameters
    # file(String):: File path name
    #
    # === Return
    # true:: Always return true
    def save(file)
      File.open(file, "w") do |f|
        f.write(@raw_cert.to_pem)
      end
      true
    end
    
    # Certificate data in PEM format
    #
    # === Return
    # (String):: Certificate data
    def data
      @raw_cert.to_pem
    end
    alias :to_s :data

  end # Certificate

end # RightScale