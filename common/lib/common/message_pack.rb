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
require 'msgpack'

# Extend MessagePack to conform to load/dump interface of other serializers like JSON
# and to create internal class objects when they are encountered when unserializing
module MessagePack

  # Unserialize data and generate any msgpack_class objects within
  #
  # === Parameters
  # data(String):: MessagePack string to unserialize
  #
  # === Return
  # obj(Object):: Unserialized object
  def self.load(data)
    create(unpack(data))
  end

  # Create any msgpack_class objects nested within the unserialized data by calling
  # their associated msgpack_create method
  #
  # === Parameters
  # object(Object):: Unserialized object that may contain other objects that need to be created
  #
  # === Return
  # object(Object):: Fully unserialized object
  #
  # === Raises
  # ArgumentError:: If object to be created does not have a msgpack_create method
  def self.create(object)
    if object.is_a?(Hash)
      object.each { |k, v| object[k] = create(v) if v.is_a?(Hash) || v.is_a?(Array) }
      if klass_name = object['msgpack_class']
        klass = deep_const_get(klass_name)
        raise ArgumentError, "#{klass_name} missing msgpack_create method" unless klass.respond_to?(:msgpack_create)
        object = klass.msgpack_create(object)
      end
    elsif object.is_a?(Array)
      object = object.map { |v| v.is_a?(Hash) || v.is_a?(Array) ? create(v) : v }
    end
    object
  end

  # Serialize object
  # Any non-standard objects must have an associated to_msgpack instance method
  #
  # === Parameters
  # object(Object):: Object to be serialized
  #
  # === Return
  # (String):: Serialized object
  def self.dump(object)
    pack(object)
  end

  protected

  # Return the constant located at the specified path
  #
  # === Parameters
  # path(String):: Absolute namespace path that is of the form ::A::B::C or A::B::C,
  #   with A always being at the top level
  #
  # === Return
  # (Object):: Constant at the end of the path
  #
  # === Raises
  # ArgumentError:: If there is no constant at the given path
  def self.deep_const_get(path)
    path = path.to_s
    path.split(/::/).inject(Object) do |p, c|
      case
      when c.empty?             then p
      when p.const_defined?(c)  then p.const_get(c)
      else                      raise ArgumentError, "Cannot find const #{path}"
      end
    end
  end

end # MessagePack
