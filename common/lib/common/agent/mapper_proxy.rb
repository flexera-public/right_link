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
        
    $:.push File.dirname(__FILE__)
    require 'amqp'
  
    include AMQPHelper

    # (Hash) Pending requests; key is request token and value is hash with :result_handler value being a block
    attr_accessor :pending_requests

    # (String) Identity of the mapper proxy
    attr_accessor :identity

    # (Serializer) Serializer used for marshaling messages
    attr_accessor :serializer

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
    # id(String):: Identity of associated agent
    # opts(Hash):: Options:
    #   :callbacks(Hash):: Callbacks to be executed on specific events. Key is event (currently
    #     only :exception is supported) and value is the Proc to be called back. For :exception
    #     the parameters are exception, message being processed, and reference to agent. It gets called
    #     whenever a packet generates an exception.
    #   :format(Symbol):: Format to use for packets serialization -- :marshal, :json or :yaml or :secure
    #   :persistent(Boolean):: true instructs the AMQP broker to save messages to persistent storage so
    #     that they aren't lost when the broker is restarted. Can be overridden on a per-message basis
    #     using the request and push methods below.
    #   :retry_timeout(Numeric):: Maximum number of seconds to retry request before give up
    #   :retry_interval(Numeric):: Number of seconds before initial request retry, increases exponentially
    #   :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    #   :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #     to do requested work on EM defer thread and all else, such as pings on main thread
    #
    # === Options
    #
    def initialize(id, opts)
      @identity = id
      @options = opts || {}
      @pending_requests = {} # Only access from primary thread
      @amqp = start_amqp(@options)
      @serializer = Serializer.new(@options[:format])
      @secure = @options[:secure]
      @persistent = @options[:persistent]
      @single_threaded = @options[:single_threaded]
      @retry_timeout = nil_if_zero(@options[:retry_timeout])
      @retry_interval = nil_if_zero(@options[:retry_interval])
      @callbacks = @options[:callbacks]
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
      request = Request.new(type, payload, opts)
      request.from = @identity
      request.token = AgentIdentity.generate
      request.persistent = opts.key?(:persistent) ? opts[:persistent] : @persistent
      @pending_requests[request.token] = { :result_handler => blk }
      RightLinkLog.info("SEND #{request.to_s([:tags, :target])}")
      request_with_retry(request, request.token)
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
      push.persistent = opts.key?(:persistent) ? opts[:persistent] : @persistent
      RightLinkLog.info("SEND #{push.to_s([:tags, :target])}")
      @amqp.queue('request', :durable => true, :no_declare => @secure).
        publish(@serializer.dump(push), :persistent => push.persistent)
      true
    end

    # Handle final result
    # Use defer thread instead of primary if not single threaded, consistent with dispatcher,
    # so that all shared data is accessed from the same thread
    # Do callback if there is an exception, consistent with agent identity queue handling
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
              RightLinkLog.error("RECV #{e.message}")
              @callbacks[:exception].call(e, msg, self) rescue nil if @callbacks && @callbacks[:exception]
            end
          end
        end
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
      @amqp.queue('request', :durable => true, :no_declare => @secure).
        publish(@serializer.dump(request), :persistent => request.persistent)

      if @retry_interval && @retry_timeout && parent
        interval = @retry_interval * multiplier
        EM.add_timer(interval) do
          if @pending_requests[parent]
            count += 1
            elapsed += interval
            if elapsed <= @retry_timeout
              request.tries << request.token
              request.token = AgentIdentity.generate
              @pending_requests[parent][:retry_parent] = parent if count == 1
              @pending_requests[request.token] = @pending_requests[parent]
              RightLinkLog.info("RESEND #{request.to_s([:tags, :target, :tries])}")
              request_with_retry(request, parent, count, multiplier * 2, elapsed)
            else
              RightLinkLog.warn("RESEND TIMEOUT after #{elapsed} seconds for #{request.to_s([:tags, :target, :tries])}")
              result = OperationResult.timeout("Timeout after #{elapsed} seconds and #{count} attempts")
              handle_result(Result.new(request.token, request.reply_to, {@identity => result}, from = @identity))
            end
          end
        end
      end
      true
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
