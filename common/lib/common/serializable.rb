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
#

module RightScale

  # MessagePack and JSON serializable types that are sent to and from agents
  module Serializable

    def self.included(base)
      base.extend ClassMethods
      base.send(:include, InstanceMethods)
    end

    module ClassMethods

      # Called when deserializing MessagePack to create object
      #
      # === Parameters
      # o(Hash):: Unserialized object data
      #
      # === Return
      # (Object):: Unserialized object
      def msgpack_create(o)
        new(*o['data'])
      end

      # Called by JSON serializer to create object
      #
      # === Parameters
      # o(Hash):: Unserialized object data
      #
      # === Return
      # (Object):: Unserialized object
      def json_create(o)
        new(*o['data'])
      end

    end

    module InstanceMethods

      # Called by MessagePack serializer to serialise object's members
      #
      # === Parameters
      # *a(Array):: Pass-through to Hash's 'to_msgpack' method
      #
      # === Return
      # (String):: MessagePack representation
      def to_msgpack(*a)
        {
          'msgpack_class' => self.class.name,
          'data'          => serialized_members
        }.to_msgpack(*a)
      end

      # Called by JSON serializer to serialise object's members
      #
      # === Parameters
      # *a(Array):: Pass-through to Hash's 'to_json' method
      #
      # === Return
      # (String):: JSON representation
      def to_json(*a)
        {
          'json_class' => self.class.name,
          'data'       => serialized_members
        }.to_json(*a)
      end

      # Implement in serializable class and return array of fields
      # that should be given to constructor when deserializing
      #
      # === Raise
      # RuntimeError:: Always raised. Override in heir.
      def serialized_members
        raise NotImplemented.new("Must be implemented by #{self.class.name}")
      end

      # Use serialized members to compare two serializable instances
      #
      # === Parameters
      # other(Serializable):: Other instance to compare self to
      #
      # === Return
      # true:: If both serializable have identical serialized fields
      # false:: Otherwise
      def ==(other)
        return false unless other.respond_to?(:serialized_members)
        self.serialized_members == other.serialized_members
      end

    end

  end

  class SerializationHelper
    
    # Symbolize keys of hash, use when retrieving hashes that use symbols
    # for keys as JSON and MessagePack serialization will produce strings instead
    #
    # === Parameters
    # hash(Hash):: Hash whose keys are to be symbolized
    #
    # === Return
    # (Hash):: Hash with same values but symbol keys
    def self.symbolize_keys(hash)
      hash.inject({}) do |h, (key, value)|
        h[(key.to_sym rescue key) || key] = value
        h
      end
    end

  end # Serializable
 
end # RightScale
