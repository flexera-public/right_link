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

require 'rubygems'
require 'json'

require File.normalize_path(File.join(File.dirname(__FILE__), 'message_pack'))

module RightScale
  
  # Cascade serializer supporting MessagePack and JSON serialization formats
  # as well as secure serialization
  class Serializer

    class SerializationError < StandardError
      attr_accessor :action, :packet
      def initialize(action, packet, serializers, msg = nil)
        @action, @packet = action, packet
        msg = ":\n#{msg}" if msg && !msg.empty?
        super("Could not #{action} packet using #{serializers.inspect}: #{msg}")
      end
    end # SerializationError

    # (Symbol) Serialization format: :msgpack, :json, or :secure
    attr_reader :format

    # Initialize the serializer
    # Do not cascade serializers if secure is specified
    #
    # === Parameters
    # preferred_format(Symbol|String):: Preferred serialization format: :msgpack, :json, or :secure
    #
    # === Raises
    # ArgumentError:: If preferred format is not supported
    def initialize(preferred_format = nil)
      @format = (preferred_format ||= :msgpack).to_sym
      if @format == :secure
        @serializers = [ SecureSerializer ]
      else
        preferred_serializer = SERIALIZERS[@format.to_sym]
        raise ArgumentError, "Serializer format #{@format.inspect} not one of #{SERIALIZERS.keys}" unless preferred_serializer
        @serializers = SERIALIZERS.values.clone
        @serializers.unshift(@serializers.delete(preferred_serializer)) if preferred_serializer
      end
    end

    # Serialize object
    #
    # === Parameters
    # packet(Object):: Object to be serialized
    #
    # === Return
    # (String):: Serialized object
    def dump(packet)
      cascade_serializers(:dump, packet)
    end

    # Unserialize object
    #
    # === Parameters
    # packet(String):: Data representing serialized object
    #
    # === Return
    # (Object):: Unserialized object
    def load(packet)
      cascade_serializers(:load, packet)
    end

    # Determine whether data is serialized in JSON format as opposed to MessagePack
    #
    # === Parameters
    # packet(String):: Data representing serialized object
    #
    # === Return
    # (Boolean):: true if packet is in JSON format, otherwise false
    def self.json?(packet)
      packet[0, 1] == "{"
    end

    private

    # Supported serialization formats
    SERIALIZERS = {:msgpack => MessagePack, :json => JSON}.freeze

    # Apply serializers in order until one succeeds
    #
    # === Parameters
    # action(Symbol):: Serialization action: :dump or :load
    # packet(Object|String):: Object or serialized data on which action is to be performed
    #
    # === Return
    # (String|Object):: Result of serialization action
    #
    # === Raises
    # SerializationError:: If none of the serializers can perform the requested action
    def cascade_serializers(action, packet)
      errors = []
      @serializers.map do |serializer|
        begin
          obj = serializer.__send__(action, packet)
        rescue Exception => e
          obj = nil
          errors << RightLinkLog.format(e)
        end
        return obj if obj
      end
      raise SerializationError.new(action, packet, @serializers, errors.join("\n"))
    end

  end # Serializer
  
end # RightScale
