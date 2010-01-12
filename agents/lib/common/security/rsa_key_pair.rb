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

  # Allows generating RSA key pairs and extracting public key component
  # Note: Creating a RSA key pair can take a fair amount of time (seconds)
  class RsaKeyPair
    
    DEFAULT_LENGTH = 2048

    # Underlying OpenSSL keys
    attr_reader :raw_key

    # Create new RSA key pair using 'length' bits
    def initialize(length = DEFAULT_LENGTH)
      @raw_key = OpenSSL::PKey::RSA.generate(length)
    end

    # Does key pair include private key?
    def has_private?
      raw_key.private?
    end
    
    # New RsaKeyPair instance with identical public key but no private key
    def to_public
      RsaKeyPair.from_data(raw_key.public_key.to_pem)
    end
    
    # Key material in PEM format
    def data
      raw_key.to_pem
    end
    alias :to_s :data
    
    # Load key pair previously serialized via 'data'    
    def self.from_data(data)
      res = RsaKeyPair.allocate
      res.instance_variable_set(:@raw_key, OpenSSL::PKey::RSA.new(data)) 
      res
    end

    # Load key from file
    def self.load(file)
      from_data(File.read(file))
    end
    
    # Save key to file in PEM format
    def save(file)
      File.open(file, "w") do |f|
        f.write(@raw_key.to_pem)
      end
    end

  end # RsaKeyPair

end # RightScale
