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
  
  class Serializer

    class SerializationError < StandardError
      attr_accessor :action, :packet
      def initialize(action, packet, serializers, msg = nil)
        @action, @packet = action, packet
        msg = ":\n#{msg}" if msg && !msg.empty?
        super("Could not #{action} packet using #{serializers.inspect}: #{msg}")
      end
    end # SerializationError

    # The secure serializer should not be part of the cascading
    def initialize(preferred_format = :marshal)
      preferred_format ||= :marshal
      if preferred_format.to_s == 'secure'
        @serializers = [ SecureSerializer ]
      else
        preferred_serializer = SERIALIZERS[preferred_format.to_sym]
        @serializers = SERIALIZERS.values.clone
        @serializers.unshift(@serializers.delete(preferred_serializer)) if preferred_serializer
      end
    end

    def dump(packet)
      cascade_serializers(:dump, packet)
    end

    def load(packet)
      cascade_serializers(:load, packet)
    end

    private

    SERIALIZERS = {:json => JSON, :marshal => Marshal, :yaml => YAML}.freeze

    def cascade_serializers(action, packet)
      errors = []
      @serializers.map do |serializer|
        begin
          o = serializer.send(action, packet)
        rescue Exception => e
          o = nil
          errors << "#{e.message}\n\t#{e.backtrace[0]}"
        end
        return o if o
      end
      raise SerializationError.new(action, packet, @serializers, errors.join("\n"))
    end

  end # Serializer
  
end # RightScale
