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

    # Callback invoked whenever Actor is included in another module or class.
    #
    # === Parameters
    # base(Module):: Module that included Actor module
    #
    # === Return
    # true:: Always return true
    def self.included(base)
      base.class_eval do
        include RightScale::Actor::InstanceMethods
        extend  RightScale::Actor::ClassMethods
      end # base.class_eval
      true
    end # self.included
    
    module ClassMethods

      # Construct default prefix by which actor is identified in requests
      #
      # === Return
      # prefix(String):: Default prefix
      def default_prefix
        prefix = to_s.to_const_path
      end

      # Add methods to list of services supported by actor
      #
      # === Parameters
      # meths(Array):: Symbol names for methods being exposed as actor services
      #
      # === Return
      # @exposed(Array):: List of unique methods exposed
      def expose(*meths)
        @exposed ||= []
        meths.each do |meth|
          @exposed << meth unless @exposed.include?(meth)
        end
        @exposed
      end

      # Get /prefix/method paths that actor responds to
      #
      # === Parameters
      # prefix(String):: Prefix by which actor is identified in requests
      #
      # === Return
      # (Array):: /prefix/method strings
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

      # Set method called when dispatching to this actor fails
      #
      # The callback method is required to accept the following parameters:
      #   method(Symbol):: Actor method being dispatched to
      #   deliverable(Packet):: Packet delivered to dispatcher
      #   exception(Exception):: Exception raised
      #
      # === Parameters
      # proc(Proc|Symbol|String):: Procedure to be called on exception
      #
      # === Block
      # Block to be executed if no Proc provided
      #
      # === Return
      # @exception_callback(Proc):: Callback procedure
      def on_exception(proc = nil, &blk)
        raise 'No callback provided for on_exception' unless proc || blk
        @exception_callback = proc || blk
      end

      # Get exception callback procedure
      #
      # === Return
      # @exception_callback(Proc):: Callback procedure
      def exception_callback
        @exception_callback
      end
      
    end # ClassMethods     
    
    module InstanceMethods

      # Send request to another agent (through the mapper)
      #
      # === Parameters
      # args(Array):: Parameters for request
      #
      # === Block
      # Optional block to be executed
      #
      # === Return
      # (MQ::Exchange):: AMQP exchange to which request is published
      def request(*args, &blk)
        MapperProxy.instance.request(*args, &blk)
      end
      
      # Send push to another agent (through the mapper)
      #
      # === Parameters
      # args(Array):: Parameters for push
      #
      # === Return
      # (MQ::Exchange):: AMQP exchange to which push is published
      def push(*args)
        MapperProxy.instance.push(*args)
      end

      # Send tag query to mapper
      #
      # === Parameters
      # args(Array):: Parameters for tag query
      #
      # === Block
      # Optional block to be executed
      #
      # === Return
      # (MQ::Exchange):: AMQP exchange to which tag query is published
      def query_tags(*args, &blk)
        MapperProxy.instance.query_tags(*args, &blk)
      end
    end # InstanceMethods
    
  end # Actor
  
end # RightScale
