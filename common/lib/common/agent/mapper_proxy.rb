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

  # This class allows sending requests to agents without having to run a local mapper.
  # It is used by Actor.request which is used by actors that need to send requests to remote agents.
  # All requests go through the mapper for security purposes.
  class MapperProxy

    # (Integer) Seconds to wait for ping response from a mapper when checking broker connectivity
    PING_TIMEOUT = 15

    # (EM::Timer) Timer while waiting for mapper ping response
    attr_accessor :pending_ping
  
    # (Hash) Pending requests; key is request token and value is hash with :result_handler value being a block
    attr_accessor :pending_requests

    # (String) Identity of the agent using the mapper proxy
    attr_accessor :identity

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
    #   :callbacks(Hash):: Callbacks to be executed on specific events. Key is event (currently
    #     only :exception is supported) and value is the Proc to be called back. For :exception
    #     the parameters are exception, message being processed, and reference to agent. It gets called
    #     whenever a packet generates an exception.
    #   :persist(Symbol):: Instructions for the AMQP broker for saving messages to persistent storage
    #     so they aren't lost when the broker is restarted:
    #       none - do not persist any messages
    #       all - persist all push and request messages
    #       push - only persist one-way request messages
    #       request - only persist two-way request messages and their associated result
    #     Can be overridden on a per-message basis using the persistence option.
    #   :retry_timeout(Numeric):: Maximum number of seconds to retry request before give up
    #   :retry_interval(Numeric):: Number of seconds before initial request retry, increases exponentially
    #   :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict agents to themselves
    #   :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #     to do requested work on EM defer thread and all else, such as pings on main thread
    def initialize(agent)
      @agent = agent
      @identity = @agent.identity
      @options = @agent.options || {}
      @broker = @agent.broker
      @secure = @options[:secure]
      @persist = @options[:persist]
      @single_threaded = @options[:single_threaded]
      @retry_timeout = nil_if_zero(@options[:retry_timeout])
      @retry_interval = nil_if_zero(@options[:retry_interval])
      @callbacks = @options[:callbacks]

      # Only to be accessed from primary thread
      @pending_requests = {}
      @pending_ping = nil

      @@instance = self
    end

    # Send request to given agent through the mapper
    #
    # === Parameters
    # type(String):: The dispatch route for the request
    # payload(Object):: Payload to send.  This will get marshalled en route.
    #
    # === Block
    # Optional block used to process result
    #
    # === Return
    # true:: Always return true
    def request(type, payload = '', opts = {}, &blk)
      raise "Mapper proxy not initialized" unless identity
      # Using next_tick to ensure on primary thread since using @pending_requests
      EM.next_tick do
        request = Request.new(type, payload, opts)
        request.from = @identity
        request.token = AgentIdentity.generate
        request.persistent = opts.key?(:persistent) ? opts[:persistent] : ['all', 'request'].include?(@persist)
        @pending_requests[request.token] = {:result_handler => blk}
        request_with_retry(request, request.token)
      end
      true
    end

    # Send push to given agent through the mapper
    #
    # === Parameters
    # type(String):: The dispatch route for the request
    # payload(Object):: Payload to send.  This will get marshalled en route.
    #
    # === Return
    # true:: Always return true
    def push(type, payload = '', opts = {})
      raise "Mapper proxy not initialized" unless identity
      push = Push.new(type, payload, opts)
      push.from = @identity
      push.token = AgentIdentity.generate
      push.persistent = opts.key?(:persistent) ? opts[:persistent] : ['all', 'push'].include?(@persist)
      publish(push)
      true
    end

    # Handle final result
    # Use defer thread instead of primary if not single threaded, consistent with dispatcher,
    # so that all shared data is accessed from the same thread
    # Do callback if there is an exception, consistent with agent identity queue handling
    # Only to be called from primary thread
    #
    # === Parameters
    # res(Packet):: Packet received as result of request
    #
    # === Return
    # true:: Always return true
    def handle_result(res)
      handlers = @pending_requests.delete(res.token)
      if handlers && handlers[:result_handler]
        # Delete any pending retry requests
        parent = handlers[:retry_parent]
        @pending_requests.reject! { |k, v| k == parent || v[:retry_parent] == parent } if parent

        if @single_threaded
          EM.next_tick { handlers[:result_handler].call(res) }
        else
          EM.defer do
            begin
              handlers[:result_handler].call(res)
            rescue Exception => e
              RightLinkLog.error("RECV - Result processing error: #{e.message}")
              @callbacks[:exception].call(e, msg, self) rescue nil if @callbacks && @callbacks[:exception]
            end
          end
        end
      else
        RightLinkLog.debug("RECV - No pending request for #{res.to_s([])}")
      end
      true
    end

    protected

    # Send request with one or more retries if do not receive a result in time
    # Send timeout result if reach retry timeout limit
    # Use exponential backoff for retry spacing
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
    def request_with_retry(request, parent, count = 0, multiplier = 1, elapsed = 0)
      ids = publish(request)

      if @retry_interval && @retry_timeout && parent && !ids.empty?
        interval = @retry_interval * multiplier
        EM.add_timer(interval) do
          begin
            if @pending_requests[parent]
              count += 1
              elapsed += interval
              if elapsed <= @retry_timeout
                request.tries << request.token
                request.token = AgentIdentity.generate
                @pending_requests[parent][:retry_parent] = parent if count == 1
                @pending_requests[request.token] = @pending_requests[parent]
                request_with_retry(request, parent, count, multiplier * 2, elapsed)
              else
                RightLinkLog.warn("RESEND TIMEOUT after #{elapsed} seconds for #{request.to_s([:tags, :target, :tries])}")
                result = OperationResult.timeout("Timeout after #{elapsed} seconds and #{count} attempts")
                handle_result(Result.new(request.token, request.reply_to, {@identity => result}, from = @identity))
              end
              check_connection(ids.first) if count == 1
            end
          rescue Exception => e
            RightLinkLog.error("Failed retry for #{request.token}: #{e.message}")
          end
        end
      end
      true
    end

    # Check whether broker connection is usable by pinging a mapper via that broker
    # The connection is declared unusable if ping does not respond in PING_TIMEOUT seconds
    # The request is ignored if already checking a connection
    # Only to be called from primary thread
    #
    # === Parameters
    # id(String):: Broker identity
    #
    # === Return
    # true:: Always return true
    def check_connection(id)
      unless @pending_ping
        @pending_ping = EM::Timer.new(PING_TIMEOUT) do
          begin
            @pending_ping = nil
            RightLinkLog.warn("Mapper ping via broker #{id} timed out after #{PING_TIMEOUT} seconds, attempting to reconnect")
            @agent.connect(@broker.host(id), @broker.port(id), @broker.id_(id), @broker.priority(id), force = true)
          rescue Exception => e
            RightLinkLog.error("Failed to reconnect to broker #{id}: #{e.message}")
          end
        end
        handler = lambda do |_|
          begin
            if @pending_ping
              @pending_ping.cancel
              @pending_ping = nil
            end
          rescue Exception => e
            RightLinkLog.error("Failed to cancel mapper ping: #{e.message}")
          end
        end
        request = Request.new("/mapper/ping", nil, {:from => @identity, :token => AgentIdentity.generate})
        @pending_requests[request.token] = {:result_handler => handler}
        publish(request, [id])
      end
      true
    end

    # Publish request
    #
    # === Parameters
    # request(Push|Request):: Packet to be sent
    # ids(Array):: Identity of specific brokers to choose from
    #
    # === Return
    # ids(Array):: Identity of brokers published to
    def publish(request, ids = nil)
      begin
        exchange = {:type => :fanout, :name => "request", :options => {:durable => true, :no_declare => @secure}}
        ids = @broker.publish(exchange, request, :persistent => request.persistent,
                              :log_filter => [:tags, :target, :tries], :brokers => ids)
      rescue Exception => e
        RightLinkLog.error("Failed to publish #{request.to_s([:tags, :target, :tries])}: #{e.message}")
        ids = []
      end
      ids
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

  end # MapperProxy

end # RightScale
