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

  # This mixin provides agent actor functionality.
  #
  # To use it simply include it your class containing the functionality to be exposed:
  #
  #   class Foo
  #     include RightScale::Actor
  #     expose :bar
  #
  #     def bar(payload)
  #       # ...
  #     end
  #
  #   end
  module Actor

    def self.included(base)
      base.class_eval do 
        include RightScale::Actor::InstanceMethods
        extend  RightScale::Actor::ClassMethods
      end # base.class_eval
    end # self.included
    
    module ClassMethods
      def default_prefix
        to_s.to_const_path
      end

      def expose(*meths)
        @exposed ||= []
        meths.each do |meth|
          @exposed << meth unless @exposed.include?(meth)
        end
      end

      def provides_for(prefix)
        return [] unless @exposed
        @exposed.select do |meth|
          if instance_methods.include?(meth.to_s) or instance_methods.include?(meth.to_sym)
            true
          else
            RightLinkLog.warn("Exposing non-existing method #{meth} in actor #{name}")
            false
          end
        end.map {|meth| "/#{prefix}/#{meth}".squeeze('/')}
      end

      def on_exception(proc = nil, &blk)
        raise 'No callback provided for on_exception' unless proc || blk
        @exception_callback = proc || blk
      end

      def exception_callback
        @exception_callback
      end
      
    end # ClassMethods     
    
    module InstanceMethods
      # Send request to another agent (through the mapper)
      def request(*args, &blk)
        MapperProxy.instance.request(*args, &blk)
      end
      
      # Send push to another agent (through the mapper)
      def push(*args)
        MapperProxy.instance.push(*args)
      end

      # Send tag query to mapper
      def query_tags(*args, &blk)
        MapperProxy.instance.query_tags(*args, &blk)
      end
    end # InstanceMethods
    
  end # Actor
  
end # RightScale
