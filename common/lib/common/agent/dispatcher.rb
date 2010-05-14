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

    # (Hash) Completed requests for dup checking; key is request token and value is time when completed
    attr_reader :completed

    # (MQ) AMQP broker for queueing messages
    attr_reader :amq

    # (EM) Event machine class (exposed for unit tests)
    attr_accessor :em

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
    # :completed_timeout(Integer):: Maximum time in seconds for retaining a request for duplicate checking,
    #   defaults to :fresh_timeout if > 0, otherwise defaults to 10 minutes
    # :completed_interval(Integer):: Number of seconds between checks for removing old requests,
    #   defaults to 30 seconds
    # :dup_check(Boolean):: Whether to check for and reject duplicate requests, e.g., due to retries
    # :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    # :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #   to do requested work on event machine defer thread and all else, such as pings on main thread
    # :threadpool_size(Integer):: Number of threads in event machine thread pool
    def initialize(amq, registry, serializer, identity, options)
      @amq = amq
      @registry = registry
      @serializer = serializer
      @identity = identity
      @secure = options[:secure]
      @single_threaded = options[:single_threaded]
      @fresh_timeout = nil_if_zero(options[:fresh_timeout])
      @dup_check = options[:dup_check]
      @completed_timeout = options[:completed_timeout] || @fresh_timeout ? @fresh_timeout : (10 * 60)
      @completed_interval = options[:completed_interval] || 60
      @completed = {} # Only access from primary thread
      @em = EM
      @em.threadpool_size = (options[:threadpool_size] || 20).to_i
      setup_completion_aging if @dup_check
    end

    # Dispatch request to appropriate actor method for servicing
    # Work is done in background defer thread if single threaded option is false
    # Handle returning of result to requester including logging any exceptions
    # Reject requests that are not fresh enough or that are duplicates of work already completed
    #
    # === Parameters
    # deliverable(Request|Push):: Packet containing request
    #
    # === Return
    # r(Result):: Result from dispatched request, nil if not dispatched because dup or stale
    def dispatch(deliverable)
      if @fresh_timeout && (created_at = deliverable.created_at.to_i) > 0
        age = Time.now.to_i - created_at
        if age > @fresh_timeout
          RightLinkLog.info("REJECT STALE <#{deliverable.token}> age #{age} exceeds #{@fresh_timeout} second limit")
          return nil
        end
      end

      if @dup_check && deliverable.kind_of?(Request)
        if @completed[deliverable.token]
          RightLinkLog.info("REJECT DUP <#{deliverable.token}> of self")
          return nil
        end
        if deliverable.respond_to?(:tries) && !deliverable.tries.empty?
          deliverable.tries.each do |token|
            if @completed[token]
              RightLinkLog.info("REJECT RETRY DUP <#{deliverable.token}> of <#{token}>")
              return nil
            end
          end
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
            completed_at = Time.now.to_i
            @completed[deliverable.token] = completed_at if @dup_check && deliverable.token
            r = Result.new(deliverable.token, deliverable.reply_to, r, identity)
            RightLinkLog.info("SEND #{r.to_s([])}")
            @amq.queue(deliverable.reply_to, :durable => true, :no_declare => @secure).
              publish(serializer.dump(r), :persistent => deliverable.persistent)
          end
        rescue Exception => e
          RightLinkLog.error("Callback following dispatch failed with #{e.class.name}: #{e.message}\n #{e.backtrace.join("\n  ")}")
        end
        r # For unit tests
      end

      if @single_threaded
        @em.next_tick { callback.call(operation.call) }
      else
        @em.defer(operation, callback)
      end
    end

    private

    # Setup request completion aging
    # All operations on @completed hash are done on primary thread
    #
    # === Return
    # true:: Always return true
    def setup_completion_aging
      @em.add_periodic_timer(@completed_interval) do
        age_limit = Time.now.to_i - @completed_timeout
        @completed.reject! { |_, v| v < age_limit }
      end
      true
    end

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

    # Convert value to nil if equals 0
    #
    # === Parameters
    # value(Integer|nil):: Value to be converted
    #
    # === Return
    # (Integer|nil):: Converted value
    def nil_if_zero(value)
      if !value || value == 0 then nil else value end
    end

  end # Dispatcher
  
end # RightScale
