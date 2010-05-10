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

  # Dispatching of payload to specified actor
  class Dispatcher

    # (ActorRegistry) Registry for actors
    attr_reader :registry

    # (Serializer) Serializer used for marshaling messages
    attr_reader :serializer

    # (String) Identity of associated agent
    attr_reader :identity

    # (MQ) AMQP broker for queueing messages
    attr_reader :amq

    # (Hash) Configuration options applied in the dispatcher
    attr_reader :options

    # (EM) Event machine class (exposed for unit tests)
    attr_accessor :evmclass

    # Initialize dispatcher
    #
    # === Parameters
    # amq(MQ):: AMQP broker for queueing messages
    # registry(ActorRegistry):: Registry for actors
    # serializer(Serializer):: Serializer used for marshaling messages
    # identity(String):: Identity of associated agent
    #
    # === Options
    # :fresh_timeout(Integer):: Maximum age in seconds before a request times out and is rejected
    # :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    # :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #   to do requested work on event machine defer thread and all else, such as pings on main thread
    # :threadpool_size(Integer):: Number of threads in event machine thread pool
    def initialize(amq, registry, serializer, identity, options)
      @amq = amq
      @registry = registry
      @serializer = serializer
      @identity = identity
      @options = options
      @evmclass = EM
      @evmclass.threadpool_size = (@options[:threadpool_size] || 20).to_i
    end

    # Dispatch request to appropriate actor method for servicing
    # Work is done in background defer thread if :single_threaded option is false
    # Handles returning of result to requester including logging any exceptions
    # Rejects requests that are not fresh enough
    #
    # === Parameters
    # deliverable(Request|Push):: Packet containing request
    #
    # === Return
    # r(Result):: Result from dispatched request
    def dispatch(deliverable)
      if (created_at = deliverable.created_at.to_i) > 0 && (fresh_timeout = @options[:fresh_timeout])
        age = Time.now.to_i - created_at
        if age > fresh_timeout
          RightLinkLog.info("REJECT #{deliverable.type} because age #{age} > #{fresh_timeout} second timeout")
          return nil
        end
      end

      prefix, meth = deliverable.type.split('/')[1..-1]
      meth ||= :index
      actor = registry.actor_for(prefix)

      operation = lambda do
        begin
          args = [ deliverable.payload ]
          args.push(deliverable) if actor.method(meth).arity == 2
          actor.send(meth, *args)
        rescue Exception => e
          handle_exception(actor, meth, deliverable, e)
        end
      end
      
      callback = lambda do |r|
        begin
          if deliverable.kind_of?(Request)
            r = Result.new(deliverable.token, deliverable.reply_to, r, identity)
            RightLinkLog.info("SEND #{r.to_s([])}")
            amq.queue(deliverable.reply_to, :no_declare => options[:secure]).
              publish(serializer.dump(r), :persistent => deliverable.persistent)
          end
        rescue Exception => e
          RightLinkLog.error("Callback following dispatch failed with #{e.class.name}: #{e.message}\n #{e.backtrace.join("\n  ")}")
        end
        r # For unit tests
      end

      if @options[:single_threaded]
        @evmclass.next_tick { callback.call(operation.call) }
      else
        @evmclass.defer(operation, callback)
      end
    end

    private

    # Produce error string including message and backtrace
    #
    # === Parameters
    # e(Exception):: Exception
    #
    # === Return
    # description(String):: Error message
    def describe_error(e)
      description = "#{e.class.name}: #{e.message}\n #{e.backtrace.join("\n  ")}"
    end

    # Handle exception by logging it and calling the actors exception callback method
    #
    # === Parameters
    # actor(Actor):: Actor that failed to process request
    # meth(String):: Name of actor method being dispatched to
    # deliverable(Packet):: Packet that dispatcher is acting upon
    # e(Exception):: Exception that was raised
    #
    # === Return
    # error(String):: Error description for this exception
    def handle_exception(actor, meth, deliverable, e)
      error = describe_error(e)
      RightLinkLog.error(error)
      begin
        if actor.class.exception_callback
          case actor.class.exception_callback
          when Symbol, String
            actor.send(actor.class.exception_callback, meth.to_sym, deliverable, e)
          when Proc
            actor.instance_exec(meth.to_sym, deliverable, e, &actor.class.exception_callback)
          end
        end
      rescue Exception => e1
        error = describe_error(e1)
        RightLinkLog.error(error)
      end
      error
    end

  end # Dispatcher
  
end # RightScale
