#
# Copyright (c) 2012 RightScale Inc
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

require 'base64'
require 'encryptor'

module RightScale
  module MessageEncoder
    # creates an encoder for the given secret
    # @param [String] identity needed for SecureSerialization usually of the form (rs-instance-1111-1111)
    # @param [String] secret for encoding/decoding or nil to use agent's certificate
    def for_agent(identity, secret=nil)
      SecureSerializerEncoder.new(identity, secret)
    end
    module_function :for_agent

    class SecretSerializer
      def initialize(serializer, identity, secret)
        @serializer = serializer
        @identity = identity
        @secret = secret
      end

      # Encodes the given serializable object to text.
      #
      # @param [Object] data in form of any serializable object
      # @return [String] text representing encoded data
      def dump(data)
        serialized_data = @serializer.dump(data)
        encrypted_data = ::Encryptor.encrypt(serialized_data, :key => @secret)
        printable_data = ::Base64.encode64(encrypted_data)

        # adhere to the SecureSerializer format in case we want to roll this
        # implementation into that class and distinguish 'secure' encryption
        # from 'secret' by the presence or absence of 'signature'.
        #
        # FIX: do we want to roll them together because it will introduce a
        # dependency on the encryptor gem?
        return @serializer.dump({'id' => @identity, 'data' => printable_data, 'encrypted' => true}, :json)
      end

      # Loads an encoded serializable object from text.
      #
      # @param [String] text to decode
      # @return [Object] decoded object
      def load(text)
        hash = @serializer.load(text)
        printable_data = hash['data']  # the only relevant field in this case
        encrypted_data = ::Base64.decode64(printable_data)
        decrypted_data = ::Encryptor.decrypt(encrypted_data, :key => @secret)
        return @serializer.load(decrypted_data)
      end
    end

    # Encode/Decode using the secure serializer
    class SecureSerializerEncoder
      # @param [String] identity needed for SecureSerialization usually of the form (rs-instance-1111-1111)
      # @param [String] secret for encoding/decoding or nil to use agent's certificate
      def initialize(identity, secret=nil)
        @serializer = serializer_for_instance(identity, secret)
      end

      # Encodes the given object into a hash.
      #
      # @param [Object] data in form of any serializable object
      # @return [Hash] hash containing dumped data
      def encode(data)
        @serializer.dump(data)
      end

      # Decodes the given hash into the original object.
      #
      # @param [Hash] data as a hash containing encoded data
      # @return [Object] decoded object
      def decode(data)
        @serializer.load(data)
      end

      private

      # creates a secure serializer that produce a packet that can be
      # encoded/decoded by the instance.
      #
      # @param [String] identity needed for SecureSerialization usually of the form (rs-instance-1111-1111)
      # @param [String] secret for encoding/decoding or nil to use agent's certificate
      def serializer_for_instance(agent_id, secret=nil)
        if secret
          SecretSerializer.new(Serializer.new, agent_id, secret)
        else
          agent_type = 'instance'
          cert = Certificate.load(AgentConfig.certs_file("#{agent_type}.cert"))
          key = RsaKeyPair.load(AgentConfig.certs_file("#{agent_type}.key"))
          store = StaticCertificateStore.new(cert, key, cert, cert)
          SecureSerializer.new(Serializer.new, agent_id, store)
        end
      end
    end
  end
end
