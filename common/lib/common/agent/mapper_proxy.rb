#
# Copyright (c) 2009-2011 RightScale Inc
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

  # This class allows sending requests to agents without having to run a local mapper
  # It is used by Actor.request which is used by actors that need to send requests to remote agents
  # If requested, it will queue requests when there are no broker connections
  # All requests go through the mapper for security purposes
  class MapperProxy

    include StatsHelper

    # Minimum number of seconds between restarts of the inactivity timer
    MIN_RESTART_INACTIVITY_TIMER_INTERVAL = 60

    # Number of seconds to wait for ping response from a mapper when checking connectivity
    PING_TIMEOUT = 30

    # Factor used on each retry iteration to achieve exponential backoff
    RETRY_BACKOFF_FACTOR = 4

    # Maximum seconds to wait before starting flushing offline queue when disabling offline mode
    MAX_QUEUE_FLUSH_DELAY = 120 # 2 minutes

    # Maximum number of queued requests before triggering re-enroll vote
    MAX_QUEUED_REQUESTS = 1000

    # Number of seconds that should be spent in offline mode before triggering a re-enroll vote
    REENROLL_VOTE_DELAY = 900 # 15 minutes

    # (EM::Timer) Timer while waiting for mapper ping response
    attr_accessor :pending_ping
  
    # (Hash) Pending requests; key is request token and value is a hash
    #   :response_handler(Proc):: Block to be activated when response is received
    #   :receive_time(Time):: Time when message was received
    #   :request_kind(String):: Kind of MapperProxy request, optional
    #   :retry_parent(String):: Token for parent request in a retry situation, optional
    attr_accessor :pending_requests

    # (HABrokerClient) High availability AMQP broker client
    attr_accessor :broker

    # (String) Identity of the agent using the mapper proxy
    attr_reader :identity

    # Accessor for use by actor
    #
    # === Return
    # (MapperProxy):: This mapper proxy instance if defined, otherwise nil
    def self.instance
      @@instance if defined?(@@instance)
    end

    # Initialize mapper proxy
    #
    # === Parameters
    # agent(Agent):: Agent using this mapper proxy; uses its identity, broker, and following options:
    #   :exception_callback(Proc):: Callback with following parameters that is activated on exception events:
    #     exception(Exception):: Exception
    #     message(Packet):: Message being processed
    #     agent(Agent):: Reference to agent
    #   :retry_timeout(Numeric):: Maximum number of seconds to retry request before give up
    #   :retry_interval(Numeric):: Number of seconds before initial request retry, increases exponentially
    #   :time_to_live(Integer):: Number of seconds before a request expires and is to be ignored
    #     by the receiver, 0 means never expire
    #   :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict agents to themselves
    #   :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #     to do requested work on EM defer thread and all else, such as pings on main thread
    def initialize(agent)
      @agent = agent
      @identity = @agent.identity
      @options = @agent.options || {}
      @broker = @agent.broker
      @secure = @options[:secure]
      @single_threaded = @options[:single_threaded]
      @queueing_mode = :initializing
      @queue_running = false
      @queue_initializing = false
      @queue = []
      @reenroll_vote_count = 0
      @retry_timeout = nil_if_zero(@options[:retry_timeout])
      @retry_interval = nil_if_zero(@options[:retry_interval])
      @ping_interval = @options[:ping_interval] || 0

      # Only to be accessed from primary thread
      @pending_requests = {}
      @pending_ping = nil

      reset_stats
      @last_received = 0
      @message_received_callbacks = []
      restart_inactivity_timer if @ping_interval > 0
      @@instance = self
    end

    # Update the time this agent last received a request or response message
    # and restart the inactivity timer thus deferring the next connectivity check
    # Also forward this message receipt notification to any callbacks that have registered
    #
    # === Block
    # Optional block without parameters that is activated when a message is received
    #
    # === Return
    # true:: Always return true
    def message_received(&callback)
      if block_given?
        @message_received_callbacks << callback
      else
        @message_received_callbacks.each { |c| c.call }
        if @ping_interval > 0
          now = Time.now.to_i
          if (now - @last_received) > MIN_RESTART_INACTIVITY_TIMER_INTERVAL
            @last_received = now
            restart_inactivity_timer
          end
        end
      end
      true
    end

    # Initialize the offline queue (should be called once)
    # All requests sent prior to running this initialization are queued if they have
    # :offline_queueing enabled and then are sent once this initialization has run
    #
    # === Block
    # If a block is given it's executed before the offline queue is flushed
    # This allows sending initialization requests before queued requests are sent
    #
    # === Return
    # true:: Always return true
    def initialize_offline_queue
      unless @queue_running
        @queue_running = true
        @queue_initializing = true
      end
      true
    end

    # Switch offline queueing to online mode and flush all buffered messages
    #
    # === Return
    # true:: Always return true
    def start_offline_queue
      if @queue_initializing
        @queue_initializing = false
        flush_queue unless @queueing_mode == :offline
        @queueing_mode = :online if @queueing_mode == :initializing
      end
      true
    end

    # Send a request to a single target or multiple targets with no response expected
    # Do not persist the request en route
    # Enqueue the request if the target is not currently available
    # Never automatically retry the request
    # Set time-to-live to be forever
    # Optionally buffer the request if the agent is in offline mode
    #
    # === Parameters
    # type(String):: Dispatch route for the request; typically identifies actor and action
    # payload(Object):: Data to be sent with marshalling en route
    # target(String|Hash):: Identity of specific target, hash for selecting potentially multiple
    #   targets, or nil if routing solely using type
    #   :tags(Array):: Tags that must all be associated with a target for it to be selected
    #   :scope(Hash):: Behavior to be used to resolve tag based routing with the following keys:
    #     :account(String):: Restrict to agents with this account id
    #   :selector(Symbol):: Which of the matched targets to be selected, either :any or :all,
    #     defaults to :all
    # opts(Hash):: Additional send control options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any
    #     brokers, defaults to false
    #
    # === Return
    # true:: Always return true
    def send_push(type, payload = nil, target = nil, opts = {})
      build_push(:send_push, type, payload, target, opts)
    end

    # Send a request to a single target or multiple targets with no response expected
    # Persist the request en route to reduce the chance of it being lost at the expense of some
    # additional network overhead
    # Enqueue the request if the target is not currently available
    # Never automatically retry the request
    # Set time-to-live to be forever
    # Optionally buffer the request if the agent is in offline mode
    #
    # === Parameters
    # type(String):: Dispatch route for the request; typically identifies actor and action
    # payload(Object):: Data to be sent with marshalling en route
    # target(String|Hash):: Identity of specific target, hash for selecting potentially multiple
    #   targets, or nil if routing solely using type
    #   :tags(Array):: Tags that must all be associated with a target for it to be selected
    #   :scope(Hash):: Behavior to be used to resolve tag based routing with the following keys:
    #     :account(String):: Restrict to agents with this account id
    #   :selector(Symbol):: Which of the matched targets to be selected, either :any or :all,
    #     defaults to :all
    # opts(Hash):: Additional send control options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any
    #     brokers, defaults to false
    #
    # === Return
    # true:: Always return true
    def send_persistent_push(type, payload = nil, target = nil, opts = {})
      build_push(:send_persistent_push, type, payload, target, opts)
    end

    # Send a request to a single target with a response expected
    # Automatically retry the request if a response is not received in a reasonable amount of time
    # or if there is a non-delivery response indicating the target is not currently available
    # Timeout the request if a response is not received in time, typically configured to 2 minutes
    # Because of retries there is the possibility of duplicated requests, and these are detected and
    # discarded automatically unless the receiving agent is using a shared queue, in which case this
    # method should not be used for actions that are non-idempotent
    # Allow the request to expire per the agent's configured time-to-live, typically 1 minute
    # Optionally buffer the request if the agent is in offline mode
    # Note that receiving a response does not guarantee that the request activity has actually
    # completed since the request processing may involve other asynchronous requests
    #
    # === Parameters
    # type(String):: Dispatch route for the request; typically identifies actor and action
    # payload(Object):: Data to be sent with marshalling en route
    # target(String|Hash):: Identity of specific target, hash for selecting targets of which one is picked
    #   randomly, or nil if routing solely using type
    #   :tags(Array):: Tags that must all be associated with a target for it to be selected
    #   :scope(Hash):: Behavior to be used to resolve tag based routing with the following keys:
    #     :account(String):: Restrict to agents with this account id
    # opts(Hash):: Additional send control options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any
    #     brokers, defaults to false
    #
    # === Block
    # Required block used to process response asynchronously with the following parameter:
    #   result(Result):: Response with an OperationResult of SUCCESS, RETRY, NON_DELIVERY, or ERROR,
    #     use RightScale::OperationResult.from_results to decode
    #
    # === Return
    # true:: Always return true
    def send_retryable_request(type, payload = nil, target = nil, opts = {}, &callback)
      build_request(:send_retryable_request, type, payload, target, opts, &callback)
    end

    # Send a request to a single target with a response expected
    # Persist the request en route to reduce the chance of it being lost at the expense of some
    # additional network overhead
    # Enqueue the request if the target is not currently available
    # Never automatically retry the request if there is the possibility of the request being duplicated
    # Set time-to-live to be forever
    # Optionally buffer the request if the agent is in offline mode
    # Note that receiving a response does not guarantee that the request activity has actually
    # completed since the request processing may involve other asynchronous requests
    #
    # === Parameters
    # type(String):: Dispatch route for the request; typically identifies actor and action
    # payload(Object):: Data to be sent with marshalling en route
    # target(String|Hash):: Identity of specific target, hash for selecting targets of which one is picked
    #   randomly, or nil if routing solely using type
    #   :tags(Array):: Tags that must all be associated with a target for it to be selected
    #   :scope(Hash):: Behavior to be used to resolve tag based routing with the following keys:
    #     :account(String):: Restrict to agents with this account id
    # opts(Hash):: Additional send control options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any
    #     brokers, defaults to false
    #
    # === Block
    # Required block used to process response asynchronously with the following parameter:
    #   result(Result):: Response with an OperationResult of SUCCESS, RETRY, NON_DELIVERY, or ERROR,
    #     use RightScale::OperationResult.from_results to decode
    #
    # === Return
    # true:: Always return true
    def send_persistent_request(type, payload = nil, target = nil, opts = {}, &callback)
      build_request(:send_persistent_request, type, payload, target, opts, &callback)
    end

    # Handle response to a request
    # Only to be called from primary thread
    #
    # === Parameters
    # response(Result):: Packet received as result of request
    #
    # === Return
    # true:: Always return true
    def handle_response(response)
      token = response.token
      if response.is_a?(Result)
        if result = OperationResult.from_results(response)
          if result.non_delivery?
            @non_deliveries.update(result.content.nil? ? "nil" : result.content.inspect)
          elsif result.error?
            @result_errors.update(result.content.nil? ? "nil" : result.content.inspect)
          end
          @results.update(result.status)
        else
          @results.update(response.results.nil? ? "nil" : response.results)
        end

        if handler = @pending_requests[token]
          if result && result.non_delivery? && handler[:request_kind] == :send_retryable_request &&
             [OperationResult::TARGET_NOT_CONNECTED, OperationResult::TTL_EXPIRATION].include?(result.content)
            # Log and ignore so that timeout retry mechanism continues
            # Leave purging of associated request until final response, i.e., success response or retry timeout
            RightLinkLog.info("Non-delivery of <#{token}> because #{result.content}")
          else
            deliver(response, handler)
          end
        elsif result && result.non_delivery?
          RightLinkLog.info("Non-delivery of <#{token}> because #{result.content}")
        else
          RightLinkLog.debug("No pending request for response #{response.to_s([])}")
        end
      end
      true
    end

    # Switch to offline mode, in this mode requests are queued in memory
    # rather than sent to the mapper
    # Idempotent
    #
    # === Return
    # true:: Always return true
    def enable_offline_mode
      if offline?
        if @flushing_queue
          # If we were in offline mode then switched back to online but are still in the
          # process of flushing the in memory queue and are now switching to offline mode
          # again then stop the flushing
          @stop_flushing_queue = true
        end
      else
        RightLinkLog.info("[offline] Disconnect from broker detected, entering offline mode")
        RightLinkLog.info("[offline] Messages will be queued in memory until connection to broker is re-established")
        @offlines.update
        @queue = []
        @queueing_mode = :offline
        @reenroll_vote_timer ||= EM::Timer.new(REENROLL_VOTE_DELAY) { vote_to_reenroll(timer_trigger=true) }
      end
    end

    # Switch back to sending requests to mapper after in memory queue gets flushed
    # Idempotent
    #
    # === Return
    # true:: Always return true
    def disable_offline_mode
      if offline? && @queue_running
        RightLinkLog.info("[offline] Connection to broker re-established")
        @offlines.finish
        @reenroll_vote_timer.cancel if @reenroll_vote_timer
        @reenroll_vote_timer = nil
        @stop_flushing_queue = false
        @flushing_queue = true
        # Let's wait a bit not to flood the mapper
        EM.add_timer(rand(MAX_QUEUE_FLUSH_DELAY)) { flush_queue } if @queue_running
      end
      true
    end

    # Get age of youngest pending request
    #
    # === Return
    # age(Integer|nil):: Age in seconds of youngest request, or nil if no pending requests
    def request_age
      time = Time.now
      age = nil
      @pending_requests.each_value do |request|
        seconds = time - request[:receive_time]
        age = seconds.to_i if age.nil? || seconds < age
      end
      age
    end

    # Create displayable dump of unfinished request information
    # Truncate list if there are more than 50 requests
    #
    # === Return
    # info(Array(String)):: Receive time and token for each request in descending time order
    def dump_requests
      info = []
      @pending_requests.each do |token, request|
        info << "#{request[:receive_time].localtime} <#{token}>"
      end
      info.sort.reverse
      info = info[0..49] + ["..."] if info.size > 50
      info
    end

    # Get mapper proxy statistics
    #
    # === Parameters
    # reset(Boolean):: Whether to reset the statistics after getting the current ones
    #
    # === Return
    # stats(Hash):: Current statistics:
    #   "exceptions"(Hash|nil):: Exceptions raised per category, or nil if none
    #     "total"(Integer):: Total exceptions for this category
    #     "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    #   "non-deliveries"(Hash|nil):: Non-delivery activity stats with keys "total", "percent", "last",
    #     and 'rate' with percentage breakdown per reason, or nil if none
    #   "offlines"(Hash|nil):: Offline activity stats with keys "total", "last", and "duration",
    #     or nil if none
    #   "pings"(Hash|nil):: Request activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown for "success" vs. "timeout", or nil if none
    #   "request kinds"(Hash|nil):: Request kind activity stats with keys "total", "percent", and "last"
    #     with percentage breakdown per kind, or nil if none
    #   "requests"(Hash|nil):: Request activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per request type, or nil if none
    #   "requests pending"(Hash|nil):: Number of requests waiting for response and age of oldest, or nil if none
    #   "response time"(Float):: Average number of seconds to respond to a request recently
    #   "result errors"(Hash|nil):: Error result activity stats with keys "total", "percent", "last",
    #     and 'rate' with percentage breakdown per error, or nil if none
    #   "results"(Hash|nil):: Results activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per operation result type, or nil if none
    #   "retries"(Hash|nil):: Retry activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per request type, or nil if none
    def stats(reset = false)
      offlines = @offlines.all
      offlines.merge!("duration" => @offlines.avg_duration) if offlines
      requests_pending = if @pending_requests.size > 0
        now = Time.now.to_i
        oldest = @pending_requests.values.inject(0) { |m, r| [m, now - r[:receive_time].to_i].max }
        {"total" => @pending_requests.size, "oldest age" => oldest}
      end
      stats = {
        "exceptions"       => @exceptions.stats,
        "non-deliveries"   => @non_deliveries.all,
        "offlines"         => offlines,
        "pings"            => @pings.all,
        "request kinds"    => @request_kinds.all,
        "requests"         => @requests.all,
        "requests pending" => requests_pending,
        "response time"    => @requests.avg_duration,
        "result errors"    => @result_errors.all,
        "results"          => @results.all,
        "retries"          => @retries.all
      }
      reset_stats if reset
      stats
    end

    protected

    # Reset dispatch statistics
    #
    # === Return
    # true:: Always return true
    def reset_stats
      @pings = ActivityStats.new
      @retries = ActivityStats.new
      @requests = ActivityStats.new
      @results = ActivityStats.new
      @result_errors = ActivityStats.new
      @non_deliveries = ActivityStats.new
      @offlines = ActivityStats.new(measure_rate = false)
      @request_kinds = ActivityStats.new(measure_rate = false)
      @exceptions = ExceptionStats.new(@agent, @options[:exception_callback])
      true
    end

    # Build and send Push packet
    #
    # === Parameters
    # kind(Symbol):: Kind of push: :send_push or :send_persistent_push
    # type(String):: Dispatch route for the request; typically identifies actor and action
    # payload(Object):: Data to be sent with marshalling en route
    # target(String|Hash):: Identity of specific target, or hash for selecting potentially multiple
    #   targets, or nil if routing solely using type
    #   :tags(Array):: Tags that must all be associated with a target for it to be selected
    #   :scope(Hash):: Behavior to be used to resolve tag based routing with the following keys:
    #     :account(String):: Restrict to agents with this account id
    #   :selector(Symbol):: Which of the matched targets to be selected, either :any or :all,
    #     defaults to :all
    # opts(Hash):: Additional send control options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any
    #     brokers, defaults to false
    #
    # === Return
    # true:: Always return true
    def build_push(kind, type, payload = nil, target = nil, opts = {})
      if should_queue?(opts)
        queue_request(:kind => kind, :type => type, :payload => payload, :target => target, :options => opts)
      else
        method = type.split('/').last
        @requests.update(method)
        push = Push.new(type, payload)
        push.from = @identity
        push.token = AgentIdentity.generate
        if target.is_a?(Hash)
          push.tags = target[:tags] || []
          push.scope = target[:scope]
          push.selector = target[:selector] || :all
        else
          push.target = target
        end
        push.persistent = kind == :send_persistent_push
        @request_kinds.update((push.selector == :all ? kind.to_s.sub(/push/, "fanout") : kind.to_s)[5..-1])
        publish(push)
      end
      true
    end

    # Build and send Request packet
    #
    # === Parameters
    # kind(Symbol):: Kind of request: :send_retryable_request or :send_persistent_request
    # type(String):: Dispatch route for the request; typically identifies actor and action
    # payload(Object):: Data to be sent with marshalling en route
    # target(String|Hash):: Identity of specific target, or hash for selecting targets of which one is picked
    #   randomly, or nil if routing solely using type
    #   :tags(Array):: Tags that must all be associated with a target for it to be selected
    #   :scope(Hash):: Behavior to be used to resolve tag based routing with the following keys:
    #     :account(String):: Restrict to agents with this account id
    # opts(Hash):: Additional send control options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any
    #     brokers, defaults to false
    #
    # === Block
    # Required block used to process response asynchronously with the following parameter:
    #   result(Result):: Response with an OperationResult of SUCCESS, RETRY, NON_DELIVERY, or ERROR,
    #     use RightScale::OperationResult.from_results to decode
    #
    # === Return
    # true:: Always return true
    def build_request(kind, type, payload, target, opts, &callback)
      if should_queue?(opts)
        queue_request(:kind => kind, :type => type, :payload => payload,
                      :target => target, :options => opts, :callback => callback)
      else
        method = type.split('/').last
        token = AgentIdentity.generate
        non_duplicate = kind == :send_persistent_request
        received_at = @requests.update(method, token)
        @request_kinds.update(kind.to_s[5..-1])

        # Using next_tick to ensure on primary thread since using @pending_requests
        EM.next_tick do
          begin
            request = Request.new(type, payload)
            request.from = @identity
            request.token = token
            if target.is_a?(Hash)
              request.tags = target[:tags] || []
              request.scope = target[:scope]
              request.selector = :any
            else
              request.target = target
            end
            request.expires_at = Time.now.to_i + @options[:time_to_live] if !non_duplicate && @options[:time_to_live] && @options[:time_to_live] != 0
            request.persistent = non_duplicate
            @pending_requests[token] = {
              :response_handler => callback,
              :receive_time => received_at,
              :request_kind => kind}
            if non_duplicate
              publish(request)
            else
              publish_with_timeout_retry(request, token)
            end
          rescue Exception => e
            RightLinkLog.error("Failed to send #{type} #{kind.to_s}", e, :trace)
            @exceptions.track(kind.to_s, e, request)
          end
        end
      end
      true
    end

    # Publish request with one or more retries if do not receive a response in time
    # Send timeout result if reach configured retry timeout limit
    # Use exponential backoff with RETRY_BACKOFF_FACTOR for retry spacing
    # Adjust retry interval by average response time to avoid adding to system load
    # when system gets slow
    #
    # === Parameters
    # request(Request):: Request to be sent
    # parent(String):: Token for original request
    # count(Integer):: Number of retries so far
    # multiplier(Integer):: Multiplier for retry interval for exponential backoff
    # elapsed(Integer):: Elapsed time in seconds since this request was first attempted
    #
    # === Return
    # true:: Always return true
    def publish_with_timeout_retry(request, parent, count = 0, multiplier = 1, elapsed = 0)
      ids = publish(request)

      if @retry_interval && @retry_timeout && parent && !ids.empty?
        interval = [(@retry_interval * multiplier) + (@requests.avg_duration || 0), @retry_timeout - elapsed].min
        EM.add_timer(interval) do
          begin
            if handler = @pending_requests[parent]
              count += 1
              elapsed += interval
              if elapsed < @retry_timeout
                request.tries << request.token
                request.token = AgentIdentity.generate
                @pending_requests[parent][:retry_parent] = parent if count == 1
                @pending_requests[request.token] = @pending_requests[parent]
                publish_with_timeout_retry(request, parent, count, multiplier * RETRY_BACKOFF_FACTOR, elapsed)
                @retries.update(request.type.split('/').last)
              else
                RightLinkLog.warn("RE-SEND TIMEOUT after #{elapsed.to_i} seconds for #{request.to_s([:tags, :target, :tries])}")
                result = OperationResult.non_delivery(OperationResult::RETRY_TIMEOUT)
                @non_deliveries.update(result.content)
                handle_response(Result.new(request.token, request.reply_to, result, @identity))
              end
              check_connection(ids.first) if count == 1
            end
          rescue Exception => e
            RightLinkLog.error("Failed retry for #{request.token}", e, :trace)
            @exceptions.track("retry", e, request)
          end
        end
      end
      true
    end

    # Publish request
    # Use mandatory flag to request return of message if it cannot be delivered
    #
    # === Parameters
    # request(Push|Request):: Packet to be sent
    # ids(Array|nil):: Identity of specific brokers to choose from, or nil if any okay
    #
    # === Return
    # ids(Array):: Identity of brokers published to
    def publish(request, ids = nil)
      begin
        exchange = {:type => :fanout, :name => "request", :options => {:durable => true, :no_declare => @secure}}
        ids = @broker.publish(exchange, request, :persistent => request.persistent, :mandatory => true,
                              :log_filter => [:tags, :target, :tries, :persistent], :brokers => ids)
      rescue HABrokerClient::NoConnectedBrokers => e
        RightLinkLog.error("Failed to publish request #{request.to_s([:tags, :target, :tries])}", e)
        ids = []
      rescue Exception => e
        RightLinkLog.error("Failed to publish request #{request.to_s([:tags, :target, :tries])}", e, :trace)
        @exceptions.track("publish", e, request)
        ids = []
      end
      ids
    end

    # Deliver the response and remove associated request(s) from pending
    # Use defer thread instead of primary if not single threaded, consistent with dispatcher,
    # so that all shared data is accessed from the same thread
    # Do callback if there is an exception, consistent with agent identity queue handling
    # Only to be called from primary thread
    #
    # === Parameters
    # response(Result):: Packet received as result of request
    # handler(Hash):: Associated request handler
    #
    # === Return
    # true:: Always return true
    def deliver(response, handler)
      @requests.finish(handler[:receive_time], response.token)

      @pending_requests.delete(response.token)
      if parent = handler[:retry_parent]
        @pending_requests.reject! { |k, v| k == parent || v[:retry_parent] == parent }
      end

      if handler[:response_handler]
        EM.__send__(@single_threaded ? :next_tick : :defer) do
          begin
            handler[:response_handler].call(response)
          rescue Exception => e
            RightLinkLog.error("Failed processing response {response.to_s([])}", e, :trace)
            @exceptions.track("response", e, response)
          end
        end
      end
      true
    end

    # Check whether broker connection is usable by pinging a mapper via that broker
    # Attempt to reconnect if ping does not respond in PING_TIMEOUT seconds
    # Ignore request if already checking a connection
    # Only to be called from primary thread
    #
    # === Parameters
    # id(String):: Identity of specific broker to use to send ping, defaults to any
    #   currently connected broker
    #
    # === Return
    # true:: Always return true
    def check_connection(id = nil)
      unless @pending_ping || (id && !@broker.connected?(id))
        @pending_ping = EM::Timer.new(PING_TIMEOUT) do
          begin
            @pings.update("timeout")
            @pending_ping = nil
            RightLinkLog.warn("Mapper ping via broker #{id} timed out after #{PING_TIMEOUT} seconds, attempting to reconnect")
            host, port, index, priority, _ = @broker.identity_parts(id)
            @agent.connect(host, port, index, priority, force = true)
          rescue Exception => e
            RightLinkLog.error("Failed to reconnect to broker #{id}", e, :trace)
            @exceptions.track("ping timeout", e)
          end
        end

        handler = lambda do |_|
          begin
            if @pending_ping
              @pings.update("success")
              @pending_ping.cancel
              @pending_ping = nil
            end
          rescue Exception => e
            RightLinkLog.error("Failed to cancel mapper ping", e, :trace)
            @exceptions.track("cancel ping", e)
          end
        end

        request = Request.new("/mapper/ping", nil, {:from => @identity, :token => AgentIdentity.generate})
        @pending_requests[request.token] = {:response_handler => handler, :receive_time => Time.now}
        ids = [id] if id
        id = publish(request, ids).first
      end
      true
    end

    # Vote for re-enrollment and reset trigger
    #
    # === Parameters
    # timer_trigger(Boolean):: true if vote was triggered by timer, false if it
    #                          was triggered by number of messages in in-memory queue
    def vote_to_reenroll(timer_trigger)
      RightScale::ReenrollManager.vote
      if timer_trigger
        @reenroll_vote_timer = EM::Timer.new(REENROLL_VOTE_DELAY) { vote_to_reenroll(timer_trigger = true) }
      else
        @reenroll_vote_count = 0
      end
    end

    # Is agent currently offline?
    #
    # === Return
    # offline(Boolean):: true if agent is disconnected or not initialized
    def offline?
      offline = @queueing_mode == :offline || !@queue_running
    end

    # Start timer that waits for inactive messaging period to end before checking connectivity
    #
    # === Return
    # true:: Always return true
    def restart_inactivity_timer
      @timer.cancel if @timer
      @timer = EM::Timer.new(@ping_interval) do
        begin
          check_connection
        rescue Exception => e
          RightLinkLog.error("Failed connectivity check", e, :trace)
        end
      end
      true
    end

    # Should agent be queueing current request?
    #
    # === Parameters
    # opts(Hash):: Request options
    #   :offline_queueing(Boolean):: Whether to queue request if currently not connected to any brokers
    #
    # enabled(Boolean):: Whether enabled to queue requests if not connected to any brokers
    #
    # === Return
    # (Boolean):: true if should queue request, otherwise false
    def should_queue?(opts)
      opts[:offline_queueing] && offline? && !@flushing_queue
    end

    # Queue given request in memory
    #
    # === Parameters
    # request(Hash):: Request to be stored
    #
    # === Return
    # true:: Always return true
    def queue_request(request)
      @reenroll_vote_count += 1 if @queue_running
      vote_to_reenroll(timer_trigger = false) if @reenroll_vote_count >= MAX_QUEUED_REQUESTS
      if @queue_initializing
        # We are in the initialization callback, requests should be put at the head of the queue
        @queue.unshift(request)
      else
        @queue << request
      end
      true
    end

    # Flush in memory queue of requests that were stored while in offline mode
    # Do this asynchronously to allow for agents to respond to requests
    # Once all in-memory requests have been flushed, switch off offline mode
    #
    # === Return
    # true:: Always return true
    def flush_queue
      if @stop_flushing_queue
        @stop_flushing_queue = false
        @flushing_queue = false
      else
        RightLinkLog.info("[offline] Starting to flush request queue of size #{@queue.size}") unless @queueing_mode == :initializing
        unless @queue.empty?
          r = @queue.shift
          if r[:callback]
            MapperProxy.instance.__send__(r[:kind], r[:type], r[:payload], r[:target], r[:options]) { |res| r[:callback].call(res) }
          else
            MapperProxy.instance.__send__(r[:kind], r[:type], r[:payload], r[:target], r[:options])
          end
        end
        if @queue.empty?
          RightLinkLog.info("[offline] Request queue flushed, resuming normal operations") unless @queueing_mode == :initializing
          @queueing_mode = :online
          @flushing_queue = false
        else
          EM.next_tick { flush_queue }
        end
      end
    end

  end # MapperProxy

end # RightScale
