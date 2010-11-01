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

    # (Integer) Seconds between registrations because of stale requests
    ADVERTISE_INTERVAL = 5 * 60

    # (ActorRegistry) Registry for actors
    attr_reader :registry

    # (String) Identity of associated agent
    attr_reader :identity

    # (Hash) Completed requests for dup checking; key is request token and value is time when completed
    attr_reader :completed

    # (HA_MQ) High availability AMQP broker
    attr_reader :broker

    # (EM) Event machine class (exposed for unit tests)
    attr_accessor :em

    # Initialize dispatcher
    #
    # === Parameters
    # agent(Agent):: Agent using this mapper proxy; uses its identity, broker, registry, and following options:
    #   :fresh_timeout(Integer):: Maximum age in seconds before a request times out and is rejected
    #   :completed_timeout(Integer):: Maximum time in seconds for retaining a request for duplicate checking,
    #     defaults to :fresh_timeout if > 0, otherwise defaults to 10 minutes
    #   :completed_interval(Integer):: Number of seconds between checks for removing old requests,
    #     defaults to 30 seconds
    #   :dup_check(Boolean):: Whether to check for and reject duplicate requests, e.g., due to retries
    #   :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict agents to themselves
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
      @fresh_timeout = nil_if_zero(options[:fresh_timeout])
      @dup_check = options[:dup_check]
      @completed_timeout = options[:completed_timeout] || @fresh_timeout ? @fresh_timeout : (10 * 60)
      @completed_interval = options[:completed_interval] || 60
      @completed = {} # Only access from primary thread
      @pending_dispatches = 0
      @last_advertise_time = 0
      @em = EM
      @em.threadpool_size = (options[:threadpool_size] || 20).to_i
      setup_completion_aging if @dup_check
      reset_stats
    end

    # Dispatch request to appropriate actor method for servicing
    # Work is done in background defer thread if single threaded option is false
    # Handle returning of result to requester including logging any exceptions
    # Reject requests that are not fresh enough or that are duplicates of work already completed
    # For stale requests report them to mapper and periodically advertise services in case mappers
    # do not have accurate clock skew for this agent
    #
    # === Parameters
    # request(Request|Push):: Packet containing request
    #
    # === Return
    # r(Result):: Result from dispatched request, nil if not dispatched because dup or stale
    def dispatch(request)
      prefix, method = request.type.split('/')[1..-1]
      method ||= :index
      received_at = @requests.update(method, (request.token if request.kind_of?(Request)))

      if @fresh_timeout && (created_at = request.created_at) > 0
        age = received_at.to_i - created_at.to_i
        if age > @fresh_timeout
          @rejects.update("stale (#{method})")
          RightLinkLog.info("REJECT STALE <#{request.token}> age #{age} exceeds #{@fresh_timeout} second limit")
          if (received_at - @last_advertise_time).to_i > ADVERTISE_INTERVAL
            @last_advertise_time = received_at
            @agent.advertise_services
          end
          if request.respond_to?(:reply_to)
            packet = Stale.new(@identity, request.token, request.from, created_at, received_at.to_f, @fresh_timeout)
            exchange = {:type => :queue, :name => request.reply_to, :options => {:durable => true, :no_declare => @secure}}
            @broker.publish(exchange, packet, :persistent => request.persistent)
          end
          return nil
        end
      end

      if @dup_check && request.kind_of?(Request)
        if @completed[request.token]
          @rejects.update("duplicate (#{method})")
          RightLinkLog.info("REJECT DUP <#{request.token}> of self")
          return nil
        end
        if request.respond_to?(:tries) && !request.tries.empty?
          request.tries.each do |token|
            if @completed[token]
              @rejects.update("retry duplicate (#{method})")
              RightLinkLog.info("REJECT RETRY DUP <#{request.token}> of <#{token}>")
              return nil
            end
          end
        end
      end

      actor = registry.actor_for(prefix)

      operation = lambda do
        begin
          if request.kind_of?(Request)
            @pending_dispatches += 1
            @last_request_dispatch_time = received_at.to_i
          end
          args = [ request.payload ]
          args.push(request) if actor.method(method).arity == 2
          actor.__send__(method, *args)
        rescue Exception => e
          @pending_dispatches = [@pending_dispatches - 1, 0].max if request.kind_of?(Request)
          handle_exception(actor, method, request, e)
        end
      end
      
      callback = lambda do |r|
        begin
          if request.kind_of?(Request)
            @pending_dispatches = [@pending_dispatches - 1, 0].max
            completed_at = @requests.finish(received_at, request.token)
            @completed[request.token] = completed_at if @dup_check && request.token
            r = Result.new(request.token, request.reply_to, r, identity, request.from, request.tries, request.persistent)
            exchange = {:type => :queue, :name => request.reply_to, :options => {:durable => true, :no_declare => @secure}}
            @broker.publish(exchange, r, :persistent => request.persistent, :log_filter => [:tries, :persistent])
          end
        rescue Exception => e
          RightLinkLog.error("Failed to publish result of dispatched request: #{e}")
          @exceptions.track("publish response", e)
        end
        r # For unit tests
      end

      if @single_threaded
        @em.next_tick { callback.call(operation.call) }
      else
        @em.defer(operation, callback)
      end
    end

    # Determine age of youngest Request dispatch
    #
    # === Return
    # age(Integer|nil):: Age in seconds of youngest dispatch, or nil if none
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
    #   "duplicate cache"(Integer|nil):: Size of cache of completed requests used for detecting duplicates, or nil if empty
    #   "exceptions"(Hash):: Exceptions raised per category
    #     "total"(Integer):: Total for category
    #     "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    #   "reject last"(Hash):: Last reject information with keys "type", "elapsed", and "active"
    #   "reject rate"(Float):: Average number of rejects per second recently
    #   "rejects"(Hash):: Total number of rejects and percentage breakdown per reason ("duplicate (<method>)",
    #     "retry duplicate (<method>)", or "stale (<method>)") as hash with keys "total" and "percent"
    #   "request last"(Hash):: Last request information with keys "type", "elapsed", and "active"
    #   "request rate"(Float):: Average number of requests per second recently
    #   "requests(Hash):: Total requests and percentage breakdown per type as hash with keys "total" and "percent"
    #   "response time"(Float):: Average number of seconds to respond to a request recently
    def stats(reset = false)
      size = @completed.size
      stats = {"duplicate cache" => size > 0 ? size : nil, "exceptions" => @exceptions.stats,
               "reject last" => @rejects.last, "reject rate" => @rejects.avg_rate,
               "rejects" => @rejects.percentage, "request last" => @requests.last,
               "request rate" => @requests.avg_rate, "requests" => @requests.percentage,
               "response time" => @requests.avg_duration}
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

    # Setup request completion aging
    # All operations on @completed hash are done on primary thread
    #
    # === Return
    # true:: Always return true
    def setup_completion_aging
      @em.add_periodic_timer(@completed_interval) do
        age_limit = Time.now - @completed_timeout
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
      error = describe_error(e)
      RightLinkLog.error(error)
      begin
        if actor.class.exception_callback
          case actor.class.exception_callback
          when Symbol, String
            actor.send(actor.class.exception_callback, method.to_sym, request, e)
          when Proc
            actor.instance_exec(method.to_sym, request, e, &actor.class.exception_callback)
          end
        end
      rescue Exception => e1
        error = describe_error(e1)
        RightLinkLog.error(error)
      end
      @exceptions.track("/#{actor.class.name}/#{method}", e)
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
