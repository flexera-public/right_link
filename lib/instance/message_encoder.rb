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

module RightScale
  class MessageEncoder
    # creates an encoder for the agent identified by "identity"
    def self.for_agent(identity)
      SecureSerializerEncoder.new(identity)
    end

    # creates a encoder for the current agent
    def self.for_current_agent
      for_agent(current_agent_identity)
    end

    # agent identity
    def self.current_agent_identity
      InstanceState.identity
    end

    # Encode/Decode using the secure serializer
    class SecureSerializerEncoder
      #
      # === Parameters
      # identity(String):: agent identity needed for SecureSerialization usually of the form (rs-instance-1111-1111)
      def initialize(identity)
        @serializer = serializer_for_instance(identity)
      end

      # encode/serialize a given object into an encrypted bundle of data
      #
      # === Parameters
      # data (Object):: Any ruby object that can be serialized
      #
      # === Returns
      # (Hash) :: {:data => given object serialized and encrypted, :id => identity, :encrypted => true}
      def encode(data)
        @serializer.dump(data)
      end

      # decode a given hash into the original object
      #
      # === Parameters
      # data (Hash):: {:data => object serialized and encrypted, :id => identity, :encrypted => true}
      #
      # === Returns
      # (Object) :: data portion of input unencrypted and serialized into the original object
      def decode(data)
        @serializer.load(data)
      end

      private
      # creates a secure serializer that produce a packet that can be encoded/decoded by the instance
      def serializer_for_instance(agent_id)
        agent_type = 'instance'
        cert = Certificate.load(AgentConfig.certs_file("#{agent_type}.cert"))
        key = RsaKeyPair.load(AgentConfig.certs_file("#{agent_type}.key"))
        store = StaticCertificateStore.new(cert, cert)
        SecureSerializer.new(Serializer.new, agent_id, cert, key, store)
      end
    end
  end
end