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

    # (Hash) Configurations options applied in this mapper proxy
    attr_accessor :options

    # (MQ) AMQP broker for queueing messages
    attr_accessor :amqp

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
    #   :format(Symbol):: Format to use for packets serialization -- :marshal, :json or :yaml or :secure
    #   :identity(String):: Identity of this agent
    #   :persistent(Boolean):: true instructs the AMQP broker to save messages to persistent storage so
    #     that they aren't lost when the broker is restarted. Default is false. Can be overridden on a
    #     per-message basis using the request and push methods of MapperProxy.
    #   :retry_interval(Numeric):: Number of seconds between request retries
    #   :retry_limit(Integer):: Maximum number of request retries before timeout
    #   :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    #   :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #     to do requested work on EM defer thread and all else, such as pings on main thread
    #
    # === Options
    #
    def initialize(id, opts)
      @options = opts || {}
      @identity = id
      @pending_requests = {}
      @amqp = start_amqp(@options)
      @serializer = Serializer.new(@options[:format])
      @@instance = self
    end

    # Send request to given agent through the mapper
    #
    # === Parameters
    # type(String):: The dispatch route for the request
    # payload(Object):: Payload to send.  This will get marshalled en route.
    #
    # === Options
    # :persistent(Boolean):: true instructs the AMQP broker to save messages to persistent storage so
    #   that they aren't lost when the broker is restarted. Default is false.
    # :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    #
    # === Block
    # Optional block used to process result
    #
    # === Return
    # true:: Always return true
    def request(type, payload = '', opts = {}, &blk)
      raise "Mapper proxy not initialized" unless identity && @options
      request = Request.new(type, payload, opts)
      request.from = @identity
      request.token = AgentIdentity.generate
      request.persistent = opts.key?(:persistent) ? opts[:persistent] : @options[:persistent]
      @pending_requests[request.token] = { :result_handler => blk }
      RightLinkLog.info("SEND #{request.to_s([:tags, :target])}")
      request_with_retry(request, nil_if_zero(:retry_interval), nil_if_zero(:retry_limit), 0)
      true
    end

    # Send push to given agent through the mapper
    #
    # === Parameters
    # type(String):: The dispatch route for the request
    # payload(Object):: Payload to send.  This will get marshalled en route.
    #
    # === Options
    # :persistent(Boolean):: true instructs the AMQP broker to save messages to persistent storage so
    #   that they aren't lost when the broker is restarted. Default is false.
    # :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    #
    # === Return
    # true:: Always return true
    def push(type, payload = '', opts = {})
      raise "Mapper proxy not initialized" unless identity && @options
      push = Push.new(type, payload, opts)
      push.from = @identity
      push.token = AgentIdentity.generate
      push.persistent = opts.key?(:persistent) ? opts[:persistent] : @options[:persistent]
      RightLinkLog.info("SEND #{push.to_s([:tags, :target])}")
      @amqp.queue('request', :durable => true, :no_declare => @options[:secure]).
        publish(@serializer.dump(push), :persistent => push.persistent)
      true
    end

    # Handle final result
    #
    # === Parameters
    # res(Packet):: Packet received as result of request
    #
    # === Return
    # true:: Always return true
    def handle_result(res)
      handlers = @pending_requests.delete(res.token)
      handlers[:result_handler].call(res) if handlers && handlers[:result_handler]
      true
    end

    protected

    # Send request with one or more retries if do not receive a result in time
    # Send timeout result if reach retry limit
    #
    # === Parameters
    # request(Request):: Request to be sent
    # retry_interval(Numeric):: Number of seconds to wait before retrying, nil means never retry
    # retry_limit(Integer):: Maximum number of retries, nil means never retry
    # retry_count(Integer):: Number of retries so far
    #
    # === Return
    # true:: Always return true
    def request_with_retry(request, retry_interval, retry_limit, retry_count)
      @amqp.queue('request', :durable => true, :no_declare => @options[:secure]).
        publish(@serializer.dump(request), :persistent => request.persistent)

      if retry_interval && retry_limit
        add_timer(retry_interval) do
          if @pending_requests[request.token]
            if retry_count < retry_limit
              RightLinkLog.info("RESEND ##{retry_count} #{request.to_s([:tags, :target])}")
              request_with_retry(request, retry_interval, retry_limit, retry_count + 1)
            else
              RightLinkLog.warn("TIMEOUT #{request.to_s([:tags, :target])}")
              attempts = retry_limit + 1
              timeout = retry_interval * attempts
              result = OperationResult.timeout("Timeout after #{timeout} seconds and #{attempts} attempts")
              from = @options[:identity]
              handle_result(Result.new(request.token, request.reply_to, {from => result}, from))
            end
          end
        end
      end
      true
    end

    # Add a one-shot timer to the EM event loop
    # Use defer thread instead of primary if not :single_threaded, consistent with dispatcher,
    # so that all shared data is accessed from the same thread
    # Log an error if the block fails
    #
    # === Parameters
    # delay(Integer):: Seconds to delay before executing block
    #
    # === Block
    # Code to be executed after the delay; must be provided
    #
    # === Return
    # true:: Always return true
    def add_timer(delay)
      blk = Proc.new do
        begin
          yield
        rescue Exception => e
          RightLinkLog.error("Time-delayed task failed with #{e.class.name}: #{e.message}\n #{e.backtrace.join("\n")}")
        end
      end

      EM.add_timer(delay) do
        if @options[:single_threaded]
          blk.call
        else
          EM.defer { blk.call }
        end
      end
      true
    end

    # Convert option value to nil if equals 0
    #
    # === Parameters
    # opt(Symbol):: Option symbol whose option value is nil or an integer
    #
    # === Return
    # (Integer):: Converted option value
    def nil_if_zero(opt)
      if !@options[opt] || @options[opt] == 0 then nil else @options[opt] end
    end

  end # MapperProxy

end # RightScale
