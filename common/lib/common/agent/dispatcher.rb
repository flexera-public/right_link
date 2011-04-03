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

    include StatsHelper

    # Cache for requests that have been dispatched recently
    # This cache is intended for use in checking for duplicate requests
    class Dispatched

      # Maximum number of seconds to retain a dispatched request in cache
      # This must be greater than the maximum possible retry timeout to avoid
      # duplicate execution of a request
      MAX_AGE = 12 * 60 * 60

      # Initialize cache
      def initialize
        @cache = {}
        @lru = []
      end

      # Store dispatched request token in cache
      #
      # === Parameters
      # token(String):: Generated message identifier
      #
      # === Return
      # true:: Always return true
      def store(token)
        now ||= Time.now.to_i
        if @cache.has_key?(token)
          @cache[token] = now
          @lru.push(@lru.delete(token))
        else
          @cache[token] = now
          @lru.push(token)
          @cache.delete(@lru.shift) while (now - @cache[@lru.first]) > MAX_AGE
        end
        true
      end

      # Fetch request
      #
      # === Parameters
      # token(String):: Generated message identifier
      #
      # === Return
      # (Boolean):: true if request has been dispatched, otherwise false
      def fetch(token)
        if @cache[token]
          @cache[token] = Time.now.to_i
          @lru.push(@lru.delete(token))
        end
      end

      # Get cache size
      #
      # === Return
      # (Integer):: Number of cache entries
      def size
        @cache.size
      end

      # Get cache statistics
      #
      # === Return
      # stats(Hash|nil):: Current statistics, or nil if cache empty
      #   "total"(Integer):: Total number in cache, or nil if none
      #   "oldest"(Integer):: Number of seconds since oldest cache entry created or updated
      #   "youngest"(Integer):: Number of seconds since youngest cache entry created or updated
      def stats
        if size > 0
          {
            "total" => size,
            "oldest age" => size > 0 ? Time.now.to_i - @cache[@lru.first] : 0,
            "youngest age" => size > 0 ? Time.now.to_i - @cache[@lru.last] : 0
          }
        end
      end

    end # Dispatched

    # (ActorRegistry) Registry for actors
    attr_reader :registry

    # (String) Identity of associated agent
    attr_reader :identity

    # (HABrokerClient) High availability AMQP broker client
    attr_reader :broker

    # (EM) Event machine class (exposed for unit tests)
    attr_accessor :em

    # Initialize dispatcher
    #
    # === Parameters
    # agent(Agent):: Agent using this mapper proxy; uses its identity, broker, registry, and following options:
    #   :dup_check(Boolean):: Whether to check for and reject duplicate requests, e.g., due to retries,
    #     but only for requests that are dispatched from non-shared queues
    #   :secure(Boolean):: true indicates to use Security features of RabbitMQ to restrict agents to themselves
    #   :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #     to do requested work on event machine defer thread and all else, such as pings on main thread
    #   :threadpool_size(Integer):: Number of threads in event machine thread pool
    def initialize(agent)
      @agent = agent
      @broker = @agent.broker
      @registry = @agent.registry
      @identity = @agent.identity
      options = @agent.options
      @secure = options[:secure]
      @single_threaded = options[:single_threaded]
      @dup_check = options[:dup_check]
      @pending_dispatches = 0
      @em = EM
      @em.threadpool_size = (options[:threadpool_size] || 20).to_i
      reset_stats

      # Only access following from primary thread
      @dispatched = Dispatched.new if @dup_check
    end

    # Dispatch request to appropriate actor for servicing
    # Handle returning of result to requester including logging any exceptions
    # Reject requests whose TTL has expired or that are duplicates of work already dispatched
    # but do not do duplicate checking if being dispatched from a shared queue
    # Work is done in background defer thread if single threaded option is false
    #
    # === Parameters
    # request(Request|Push):: Packet containing request
    # shared(Boolean):: Whether being dispatched from a shared queue
    #
    # === Return
    # r(Result):: Result from dispatched request, nil if not dispatched because dup or stale
    def dispatch(request, shared = false)

      # Determine which actor this request is for
      prefix, method = request.type.split('/')[1..-1]
      method ||= :index
      actor = @registry.actor_for(prefix)
      token = request.token
      received_at = @requests.update(method, (token if request.kind_of?(Request)))
      if actor.nil?
        RightLinkLog.error("No actor for dispatching request <#{request.token}> of type #{request.type}")
        return nil
      end

      # Reject this request if its TTL has expired
      if (expires_at = request.expires_at) && expires_at > 0 && received_at.to_i >= expires_at
        @rejects.update("expired (#{method})")
        RightLinkLog.info("REJECT EXPIRED <#{token}> from #{request.from} TTL #{elapsed(received_at.to_i - expires_at)} ago")
        if request.is_a?(Request)
          # For agents that do not know about non-delivery, use error result
          non_delivery = if request.recv_version < 13
            OperationResult.error("Could not deliver request (#{OperationResult::TTL_EXPIRATION})")
          else
            OperationResult.non_delivery(OperationResult::TTL_EXPIRATION)
          end
          result = Result.new(token, request.reply_to, non_delivery, @identity, request.from, request.tries, request.persistent)
          exchange = {:type => :queue, :name => request.reply_to, :options => {:durable => true, :no_declare => @secure}}
          @broker.publish(exchange, result, :persistent => true, :mandatory => true)
        end
        return nil
      end

      # Reject this request if it is a duplicate
      if @dup_check && !shared && request.kind_of?(Request)
        if @dispatched.fetch(token)
          @rejects.update("duplicate (#{method})")
          RightLinkLog.info("REJECT DUP <#{token}> of self")
          return nil
        end
        request.tries.each do |t|
          if @dispatched.fetch(t)
            @rejects.update("retry duplicate (#{method})")
            RightLinkLog.info("REJECT RETRY DUP <#{token}> of <#{t}>")
            return nil
          end
        end
      end

      # Proc for performing request in actor
      operation = lambda do
        begin
          @pending_dispatches += 1
          @last_request_dispatch_time = received_at.to_i
          @dispatched.store(token) if @dup_check && !shared && request.kind_of?(Request) && token
          actor.__send__(method, request.payload)
        rescue Exception => e
          @pending_dispatches = [@pending_dispatches - 1, 0].max
          handle_exception(actor, method, request, e)
        end
      end
      
      # Proc for sending response
      callback = lambda do |r|
        begin
          @pending_dispatches = [@pending_dispatches - 1, 0].max
          if request.kind_of?(Request)
            duration = @requests.finish(received_at, token)
            r = Result.new(token, request.reply_to, r, @identity, request.from, request.tries, request.persistent, duration)
            exchange = {:type => :queue, :name => request.reply_to, :options => {:durable => true, :no_declare => @secure}}
            @broker.publish(exchange, r, :persistent => true, :mandatory => true, :log_filter => [:tries, :persistent, :duration])
          end
        rescue HABrokerClient::NoConnectedBrokers => e
          RightLinkLog.error("Failed to publish result of dispatched request #{request.trace}", e)
        rescue Exception => e
          RightLinkLog.error("Failed to publish result of dispatched request #{request.trace}", e, :trace)
          @exceptions.track("publish response", e)
        end
        r # For unit tests
      end

      # Process request and send response, if any
      if @single_threaded
        @em.next_tick { callback.call(operation.call) }
      else
        @em.defer(operation, callback)
      end
    end

    # Determine age of youngest request dispatch
    #
    # === Return
    # (Integer|nil):: Age in seconds of youngest dispatch, or nil if none
    def dispatch_age
      age = Time.now.to_i - @last_request_dispatch_time if @last_request_dispatch_time && @pending_dispatches > 0
    end

    # Get dispatcher statistics
    #
    # === Parameters
    # reset(Boolean):: Whether to reset the statistics after getting the current ones
    #
    # === Return
    # stats(Hash):: Current statistics:
    #   "cached"(Hash|nil):: Number of dispatched requests cached and age of youngest and oldest,
    #     or nil if empty
    #   "exceptions"(Hash|nil):: Exceptions raised per category, or nil if none
    #     "total"(Integer):: Total for category
    #     "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    #   "rejects"(Hash|nil):: Request reject activity stats with keys "total", "percent", "last", and "rate"
    #   "pending"(Hash|nil):: Pending request "total" and "youngest age", or nil if none
    #     with percentage breakdown per reason ("duplicate (<method>)", "retry duplicate (<method>)", or
    #     "stale (<method>)"), or nil if none
    #   "requests"(Hash|nil):: Request activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per request type, or nil if none
    #   "response time"(Float):: Average number of seconds to respond to a request recently
    def stats(reset = false)
      pending = if @pending_dispatches > 0
        {
          "total" => @pending_dispatches,
          "youngest age" => dispatch_age
        }
      end
      stats = {
        "cached"        => (@dispatched.stats if @dup_check),
        "exceptions"    => @exceptions.stats,
        "pending"       => pending,
        "rejects"       => @rejects.all,
        "requests"      => @requests.all,
        "response time" => @requests.avg_duration
      }
      reset_stats if reset
      stats
    end

    private

    # Reset dispatch statistics
    #
    # === Return
    # true:: Always return true
    def reset_stats
      @rejects = ActivityStats.new
      @requests = ActivityStats.new
      @exceptions = ExceptionStats.new(@agent)
      true
    end

    # Handle exception by logging it, calling the actors exception callback method,
    # and gathering exception statistics
    #
    # === Parameters
    # actor(Actor):: Actor that failed to process request
    # method(String):: Name of actor method being dispatched to
    # request(Packet):: Packet that dispatcher is acting upon
    # e(Exception):: Exception that was raised
    #
    # === Return
    # error(String):: Error description for this exception
    def handle_exception(actor, method, request, e)
      error = RightLinkLog.format("Failed processing #{request.type}", e, :trace)
      RightLinkLog.error(error)
      begin
        if actor && actor.class.exception_callback
          case actor.class.exception_callback
          when Symbol, String
            actor.send(actor.class.exception_callback, method.to_sym, request, e)
          when Proc
            actor.instance_exec(method.to_sym, request, e, &actor.class.exception_callback)
          end
        end
        @exceptions.track(request.type, e)
      rescue Exception => e2
        RightLinkLog.error("Failed handling error for #{request.type}", e2, :trace)
        @exceptions.track(request.type, e2) rescue nil
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
