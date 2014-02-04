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
    # This wrapper class is to let the specs texts pass on windows -- the mock object doesn't
    # include the serializable class so we must serialize it as JSON. Code was taken from
    # the right_agent SecureSerializer class
    class Serializer
      include ProtocolVersionMixin

      def initialize
        @serializer = ::RightScale::Serializer.new
      end

      def dump(obj)
        serialize_format = if obj.respond_to?(:send_version) && can_handle_msgpack_result?(obj.send_version)
          @serializer.format
        else
          :json
        end
        @serializer.dump(obj, serialize_format)
      end

      def load(obj)
        serialize_format = if obj.respond_to?(:send_version) && can_handle_msgpack_result?(obj.send_version)
          @serializer.format
        else
          :json
        end
        @serializer.load(obj, serialize_format)
      end
    end

    class SecretSerializer
      # creates an encoder for the given secret
      # @param [String] identity needed for SecureSerialization usually of the form (rs-instance-1111-1111)
      # @param [String] secret for encoding/decoding
      def initialize(identity, secret)
        @serializer = ::RightScale::MessageEncoder::Serializer.new
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

        return @serializer.dump({'id' => @identity, 'data' => printable_data, 'encrypted' => true})
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
  end
end
