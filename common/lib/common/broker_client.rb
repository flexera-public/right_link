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

require File.join(File.dirname(__FILE__), 'stats_helper')

module RightScale

  # Client for accessing AMQP broker
  class BrokerClient

    include StatsHelper

    # Set of possible broker connection status values
    STATUS = [
      :connecting,   # Initiated AMQP connection but not yet confirmed that connected
      :connected,    # Confirmed AMQP connection
      :stopping,     # Broker is stopping service and, although still connected, is no longer usable
      :disconnected, # Notified by AMQP that connection has been lost and attempting to reconnect
      :closed,       # AMQP connection closed explicitly or because of too many failed connect attempts
      :failed        # Failed to connect due to internal failure or AMQP failure to connect
    ]

    # (MQ) AMQP client
    attr_reader :mq

    # (String) Broker identity
    attr_reader :identity

    # (String) Broker alias, used in logs
    attr_reader :alias

    # (String) Host name
    attr_reader :host

    # (Integer) Port number
    attr_reader :port

    # (Integer) Unique index for broker within given island, used in alias
    attr_reader :index

    # (Symbol) AMQP connection STATUS value
    attr_reader :status

    # (Array) List of MQ::Queue queues currently subscribed
    attr_reader :queues

    # (Boolean) Whether last connect attempt failed
    attr_reader :last_failed

    # (ActivityStats) AMQP lost connection statistics
    attr_reader :disconnects

    # (ActivityStats) AMQP connection failure statistics
    attr_reader :failures

    # (Integer) Number of attempts to connect after failure
    attr_reader :retries

    # (Integer) Identifier for RightNet island containing this broker
    attr_reader :island_id

    # (Integer) RightNet island alias, used in logs
    attr_reader :island_alias

    # (Boolean) Whether this broker is in the same RightNet island as the creator of this client
    attr_reader :in_home_island

    # Create broker client
    #
    # === Parameters
    # identity(String):: Broker identity
    # address(Hash):: Broker address
    #   :host(String:: IP host name or address
    #   :port(Integer):: TCP port number for individual broker
    #   :index(String):: Unique index for broker within given island for use in forming alias
    # serializer(Serializer):: Serializer used for marshaling packets being published; if nil,
    #   has same effect as setting options :no_serialize and :no_unserialize
    # exceptions(ExceptionStats):: Exception statistics container
    # options(Hash):: AMQP connection configuration options
    #   :user(String):: User name
    #   :pass(String):: Password
    #   :vhost(String):: Virtual host path name
    #   :insist(Boolean):: Whether to suppress redirection of connection
    #   :reconnect_interval(Integer):: Number of seconds between reconnect attempts
    #   :prefetch(Integer):: Maximum number of messages the AMQP broker is to prefetch for the mapper
    #     before it receives an ack. Value 1 ensures that only last unacknowledged gets redelivered
    #     if the mapper crashes. Value 0 means unlimited prefetch.
    #   :home_island(Integer):: Identifier for home island of creator of this client
    #   :exception_on_receive_callback(Proc):: Callback activated on a receive exception with parameters
    #     message(Object):: Message received
    #     exception(Exception):: Exception raised
    #   :update_status_callback(Proc):: Callback activated on a connection status change with parameters
    #     broker(BrokerClient):: Broker client
    #     connected_before(Boolean):: Whether was connected prior to this status change
    # island(IslandData|nil):: RightNet island containing this broker, or nil if unknown
    # existing(BrokerClient|nil):: Existing broker client for this address, or nil if none
    def initialize(identity, address, serializer, exceptions, options, island = nil, existing = nil)
      @options         = options
      @identity        = identity
      @island_id       = island && island.id
      @island_alias    = island ? "i#{island.id}" : ""
      @in_home_island  = @island_id == @options[:home_island]
      @host            = address[:host]
      @port            = address[:port].to_i
      @index           = address[:index].to_i
      @alias           = (@in_home_island ? "" : @island_alias) + "b#{@index}"
      @serializer      = serializer
      @exceptions      = exceptions
      @queues          = []
      @last_failed     = false
      @disconnects     = ActivityStats.new(measure_rate = false)
      @failures        = ActivityStats.new(measure_rate = false)
      @retries         = 0

      connect(address, @options[:reconnect_interval])

      if existing
        @disconnects = existing.disconnects
        @failures = existing.failures
        @last_failed = existing.last_failed
        @retries = existing.retries
        update_failure if @status == :failed
      end
    end

    # Determine whether the broker connection is usable, i.e., connecting or confirmed connected
    #
    # === Return
    # (Boolean):: true if usable, otherwise false
    def usable?
      [:connected, :connecting].include?(@status)
    end

    # Determine whether this client is currently connected to the broker
    #
    # === Return
    # (Boolean):: true if connected, otherwise false
    def connected?
      @status == :connected
    end

    # Determine whether the broker connection has failed
    #
    # === Return
    # (Boolean):: true if failed, otherwise false
    def failed?(backoff = false)
      @status == :failed
    end

    # Subscribe an AMQP queue to an AMQP exchange
    # Do not wait for confirmation from broker that subscription is complete
    # When a message is received, acknowledge, unserialize, and log it as specified
    # If the message is unserialized and it is not of the right type, it is dropped after logging a warning
    #
    # === Parameters
    # queue(Hash):: AMQP queue being subscribed with keys :name and :options,
    #   which are the standard AMQP ones plus
    #     :no_declare(Boolean):: Whether to skip declaring this queue on the broker
    #       to cause its creation; for use when client does not have permission to create or
    #       knows the queue already exists and wants to avoid declare overhead
    # exchange(Hash|nil):: AMQP exchange to subscribe to with keys :type, :name, and :options,
    #   nil means use empty exchange by directly subscribing to queue; the :options are the
    #   standard AMQP ones plus
    #     :no_declare(Boolean):: Whether to skip declaring this exchange on the broker
    #       to cause its creation; for use when client does not have create permission or
    #       knows the exchange already exists and wants to avoid declare overhead
    # options(Hash):: Subscribe options:
    #   :ack(Boolean):: Explicitly acknowledge received messages to AMQP
    #   :no_unserialize(Boolean):: Do not unserialize message, this is an escape for special
    #     situations like enrollment, also implicitly disables receive filtering and logging;
    #     this option is implicitly invoked if initialize without a serializer
    #   (packet class)(Array(Symbol)):: Filters to be applied in to_s when logging packet to :info,
    #     only packet classes specified are accepted, others are not processed but are logged with error
    #   :category(String):: Packet category description to be used in error messages
    #   :log_data(String):: Additional data to display at end of log entry
    #   :no_log(Boolean):: Disable receive logging unless debug level
    #   :exchange2(Hash):: Additional exchange to which same queue is to be bound
    #   :brokers(Array):: Identity of brokers for which to subscribe, defaults to all usable if nil or empty
    #
    # === Block
    # Block with following parameters to be called each time exchange matches a message to the queue:
    #   identity(String):: Serialized identity of broker delivering the message
    #   message(Packet|String):: Message received, which is unserialized unless :no_unserialize was specified
    #
    # === Return
    # (Boolean):: true if subscribe successfully or if already subscribed, otherwise false
    def subscribe(queue, exchange = nil, options = {}, &blk)
      return false unless usable?
      return true unless @queues.select { |q| q.name == queue[:name] }.empty?

      to_exchange =  if exchange
        if options[:exchange2]
          " to exchanges #{exchange[:name]} and #{options[:exchange2][:name]}"
        else
          " to exchange #{exchange[:name]}"
        end
      end
      queue_options = queue[:options] || {}
      exchange_options = (exchange && exchange[:options]) || {}

      begin
        RightLinkLog.info("[setup] Subscribing queue #{queue[:name]}#{to_exchange} on broker #{@alias}")
        q = @mq.queue(queue[:name], queue_options)
        @queues << q
        if exchange
          x = @mq.__send__(exchange[:type], exchange[:name], exchange_options)
          binding = q.bind(x, options[:key] ? {:key => options[:key]} : {})
          if exchange2 = options[:exchange2]
            q.bind(@mq.__send__(exchange2[:type], exchange2[:name], exchange2[:options] || {}))
          end
          q = binding
        end
        if options[:ack]
          q.subscribe(:ack => true) do |info, message|
            begin
              # Ack now before processing to avoid risk of duplication after a crash
              info.ack
              if options[:no_unserialize] || @serializer.nil?
                execute_callback(blk, @identity, message)
              elsif message == "nil"
                # This happens as part of connecting an instance agent to a broker prior to version 13
                RightLinkLog.debug("RECV #{@alias} nil message ignored")
              elsif
                packet = receive(queue[:name], message, options)
                execute_callback(blk, @identity, packet) if packet
              end
              true
            rescue Exception => e
              RightLinkLog.error("Failed executing block for message from queue #{queue.inspect}#{to_exchange} " +
                                 "on broker #{@alias}", e, :trace)
              @exceptions.track("receive", e)
              false
            end
          end
        else
          q.subscribe do |message|
            begin
              if options[:no_unserialize] || @serializer.nil?
                execute_callback(blk, @identity, message)
              elsif message == "nil"
                # This happens as part of connecting an instance agent to a broker
                RightLinkLog.debug("RECV #{@alias} nil message ignored")
              elsif
                packet = receive(queue[:name], message, options)
                execute_callback(blk, @identity, packet) if packet
              end
              true
            rescue Exception => e
              RightLinkLog.error("Failed executing block for message from queue #{queue.inspect}#{to_exchange} " +
                                 "on broker #{@alias}", e, :trace)
              @exceptions.track("receive", e)
              false
            end
          end
        end
      rescue Exception => e
        RightLinkLog.error("Failed subscribing queue #{queue.inspect}#{to_exchange} on broker #{@alias}", e, :trace)
        @exceptions.track("subscribe", e)
        false
      end
    end

    # Unsubscribe from the specified queues
    # Silently ignore unknown queues
    #
    # === Parameters
    # queue_names(Array):: Names of queues previously subscribed to
    #
    # === Block
    # Optional block to be called with no parameters when each unsubscribe completes
    #
    # === Return
    # true:: Always return true
    def unsubscribe(queue_names, &blk)
      if usable?
        @queues.each do |q|
          if queue_names.include?(q.name)
            begin
              RightLinkLog.info("[stop] Unsubscribing queue #{q.name} on broker #{@alias}")
              q.unsubscribe { blk.call if blk }
            rescue Exception => e
              RightLinkLog.error("Failed unsubscribing queue #{q.name} on broker #{@alias}", e, :trace)
              @exceptions.track("unsubscribe", e)
              blk.call if blk
            end
          end
        end
      end
      true
    end

    # Declare queue or exchange object but do not subscribe to it
    #
    # === Parameters
    # type(Symbol):: Type of object: :queue, :direct, :fanout or :topic
    # name(String):: Name of object
    # options(Hash):: Standard AMQP declare options
    #
    # === Return
    # (Boolean):: true if declare successfully, otherwise false
    def declare(type, name, options = {})
      return false unless usable?
      begin
        RightLinkLog.info("[setup] Declaring #{name} #{type.to_s} on broker #{@alias}")
        delete_from_cache(:queue, name)
        @mq.__send__(type, name, options)
        true
      rescue Exception => e
        RightLinkLog.error("Failed declaring #{type.to_s} #{name} on broker #{@alias}", e, :trace)
        @exceptions.track("declare", e)
        false
      end
    end

    # Publish message to AMQP exchange
    #
    # === Parameters
    # exchange(Hash):: AMQP exchange to subscribe to with keys :type, :name, and :options,
    #   which are the standard AMQP ones plus
    #     :no_declare(Boolean):: Whether to skip declaring this exchange or queue on the broker
    #       to cause its creation; for use when client does not have create permission or
    #       knows the object already exists and wants to avoid declare overhead
    #     :declare(Boolean):: Whether to delete this exchange or queue from the AMQP cache
    #       to force it to be declared on the broker and thus be created if it does not exist
    # packet(Packet):: Message to serialize and publish
    # message(String):: Serialized message to be published
    # options(Hash):: Publish options -- standard AMQP ones plus
    #   :no_serialize(Boolean):: Do not serialize packet because it is already serialized
    #   :log_filter(Array(Symbol)):: Filters to be applied in to_s when logging packet to :info
    #   :log_data(String):: Additional data to display at end of log entry
    #   :no_log(Boolean):: Disable publish logging unless debug level
    #
    # === Return
    # (Boolean):: true if publish successfully, otherwise false
    def publish(exchange, packet, message, options = {})
      return false unless connected?
      begin
        exchange_options = exchange[:options] || {}
        unless (options[:no_log] && RightLinkLog.level != :debug) || options[:no_serialize]
          re = "RE-" if packet.respond_to?(:tries) && !packet.tries.empty?
          log_filter = options[:log_filter] unless RightLinkLog.level == :debug
          RightLinkLog.info("#{re}SEND #{@alias} #{packet.to_s(log_filter, :send_version)} " +
                            "#{options[:log_data]}")
        end
        RightLinkLog.debug("... publish options #{options.inspect}, exchange #{exchange[:name]}, " +
                           "type #{exchange[:type]}, options #{exchange[:options].inspect}")
        delete_from_cache(exchange[:type], exchange[:name]) if exchange_options[:declare]
        @mq.__send__(exchange[:type], exchange[:name], exchange_options).publish(message, options)
        true
      rescue Exception => e
        RightLinkLog.error("Failed publishing to exchange #{exchange.inspect} on broker #{@alias}", e, :trace)
        @exceptions.track("publish", e)
        false
      end
    end

    # Provide callback to be activated when broker returns a message that could not be delivered
    # A message published with :mandatory => true is returned if the exchange does not have any associated queues
    # or if all the associated queues do not have any consumers
    # A message published with :immediate => true is returned for the same reasons as :mandatory plus if all
    # of the queues associated with the exchange are not immediately ready to consume the message
    #
    # === Block
    # Optional block with following parameters to be called when a message is returned
    #   to(String):: Queue to which message was published
    #   reason(String):: Reason for return
    #     "NO_ROUTE" - queue does not exist
    #     "NO_CONSUMERS" - queue exists but it has no consumers, or if :immediate was specified,
    #       all consumers are not immediately ready to consume
    #     "ACCESS_REFUSED" - queue not usable because broker is in the process of stopping service
    #   message(String):: Returned serialized message
    #
    # === Return
    # true:: Always return true
    def return_message
      @mq.return_message do |info, message|
        begin
          to = if info.exchange && !info.exchange.empty? then info.exchange else info.routing_key end
          reason = info.reply_text
          RightLinkLog.debug("RETURN #{@alias} because #{reason} for #{to}")
          yield(to, reason, message) if block_given?
        rescue Exception => e
          RightLinkLog.error("Failed return #{info.inspect} of message from broker #{@alias}", e, :trace)
          @exceptions.track("return", e)
        end
      end
      true
    end

    # Delete queue if subscribed to it
    #
    # === Parameters
    # name(String):: Queue name
    # options(Hash):: Queue declare options
    #
    # === Return
    # (Boolean):: true if queue was successfully deleted, otherwise false
    def delete(name, options = {})
      deleted = false
      if usable?
        begin
          @queues.reject! do |q|
            if q.name == name
              @mq.queue(name, options.merge(:no_declare => true)).delete
              deleted = true
            end
          end
        rescue Exception => e
          RightLinkLog.error("Failed deleting queue #{name.inspect} on broker #{@alias}", e, :trace)
          @exceptions.track("delete", e)
        end
      end
      deleted
    end

    # Close broker connection
    #
    # === Parameters
    # propagate(Boolean):: Whether to propagate connection status updates, defaults to true
    # normal(Boolean):: Whether this is a normal close vs. a failed connetcion, defaults to true
    # log(Boolean):: Whether to log that closing, defaults to true
    #
    # === Block
    # Optional block with no parameters to be called after connection closed
    #
    # === Return
    # true:: Always return true
    def close(propagate = true, normal = true, log = true, &blk)
      final_status = normal ? :closed : :failed
      if ![:closed, :failed].include?(@status)
        begin
          RightLinkLog.info("[stop] Closed connection to broker #{@alias}") if log
          update_status(final_status) if propagate
          @connection.close do
            @status = final_status
            yield if block_given?
          end
        rescue Exception => e
          RightLinkLog.error("Failed to close broker #{@alias}", e, :trace)
          @exceptions.track("close", e)
          @status = final_status
          yield if block_given?
        end
      else
        @status = final_status
        yield if block_given?
      end
      true
    end

    # Get broker client information summarizing its status
    #
    # === Return
    # (Hash):: Status of broker with keys
    #   :identity(String):: Serialized identity
    #   :alias(String):: Alias used in logs
    #   :status(Symbol):: Status of connection
    #   :disconnects(Integer):: Number of times lost connection
    #   :failures(Integer):: Number of times connect failed
    #   :retries(Integer):: Number of attempts to connect after failure
    def summary
      {
        :identity    => @identity,
        :alias       => @alias,
        :status      => @status,
        :retries     => @retries,
        :disconnects => @disconnects.total,
        :failures    => @failures.total,
      }
    end

    # Get broker client statistics
    #
    # === Return
    # (Hash):: Broker client stats with keys
    #  "alias"(String):: Broker alias
    #  "identity"(String):: Broker identity
    #  "status"(Status):: Status of connection
    #  "disconnect last"(Hash|nil):: Last disconnect information with key "elapsed", or nil if none
    #  "disconnects"(Integer|nil):: Number of times lost connection, or nil if none
    #  "failure last"(Hash|nil):: Last connect failure information with key "elapsed", or nil if none
    #  "failures"(Integer|nil):: Number of failed attempts to connect to broker, or nil if none
    def stats
      {
        "alias"           => @alias,
        "identity"        => @identity,
        "status"          => @status.to_s,
        "disconnect last" => @disconnects.last,
        "disconnects"     => nil_if_zero(@disconnects.total),
        "failure last"    => @failures.last,
        "failures"        => nil_if_zero(@failures.total),
        "retries"         => nil_if_zero(@retries)
      }
    end

    # Callback from AMQP with connection status or from HABrokerClient
    # Makes client callback with :connected or :disconnected status if boundary crossed
    #
    # === Parameters
    # status(Symbol):: Status of connection (:connected, :ready, :disconnected, :stopping, :failed, :closed)
    #
    # === Return
    # true:: Always return true
    def update_status(status)
      # Do not let closed connection regress to failed
      return true if status == :failed && @status == :closed

      # Wait until connection is ready (i.e. handshake with broker is completed) before
      # changing our status to connected
      return true if status == :connected
      status = :connected if status == :ready

      before = @status
      @status = status

      if status == :connected
        update_success
      elsif status == :failed
        update_failure
      elsif status == :disconnected && before != :disconnected
        @disconnects.update
      end

      unless status == before || @options[:update_status_callback].nil?
        @options[:update_status_callback].call(self, before == :connected)
      end
      true
    end

    protected

    # Connect to broker and register for status updates
    # Also set prefetch value if specified
    #
    # === Parameters
    # address(Hash):: Broker address
    #   :host(String:: IP host name or address
    #   :port(Integer):: TCP port number for individual broker
    #   :index(String):: Unique index for broker within given island for use in forming alias
    # reconnect_interval(Integer):: Number of seconds between reconnect attempts
    #
    # === Return
    # true:: Always return true
    def connect(address, reconnect_interval)
      begin
        RightLinkLog.info("[setup] Connecting to broker #{@identity}, alias #{@alias}")
        @status = :connecting
        @connection = AMQP.connect(:user               => @options[:user],
                                   :pass               => @options[:pass],
                                   :vhost              => @options[:vhost],
                                   :host               => address[:host],
                                   :port               => address[:port],
                                   :insist             => @options[:insist] || false,
                                   :reconnect_delay    => lambda { rand(reconnect_interval) },
                                   :reconnect_interval => reconnect_interval)
        @mq = MQ.new(@connection)
        @mq.__send__(:connection).connection_status { |status| update_status(status) }
        @mq.prefetch(@options[:prefetch]) if @options[:prefetch]
      rescue Exception => e
        @status = :failed
        @failures.update
        RightLinkLog.error("Failed connecting to broker #{@alias}", e, :trace)
        @exceptions.track("connect", e)
        @connection.close if @connection
      end
    end

    # Receive message by unserializing it, checking that it is an acceptable type, and logging accordingly
    #
    # === Parameters
    # queue(String):: Name of queue
    # message(String):: Serialized packet
    # options(Hash):: Subscribe options:
    #   (packet class)(Array(Symbol)):: Filters to be applied in to_s when logging packet to :info,
    #     only packet classes specified are accepted, others are not processed but are logged with error
    #   :category(String):: Packet category description to be used in error messages
    #   :log_data(String):: Additional data to display at end of log entry
    #   :no_log(Boolean):: Disable receive logging unless debug level
    #
    # === Return
    # (Packet|nil):: Unserialized packet or nil if not of right type or if there is an exception
    def receive(queue, message, options = {})
      begin
        packet = @serializer.load(message)
        if options.key?(packet.class)
          unless options[:no_log] && RightLinkLog.level != :debug
            re = "RE-" if packet.respond_to?(:tries) && !packet.tries.empty?
            log_filter = options[packet.class] unless RightLinkLog.level == :debug
            RightLinkLog.info("#{re}RECV #{@alias} #{packet.to_s(log_filter, :recv_version)} " +
                              "#{options[:log_data]}")
          end
          packet
        else
          category = options[:category] + " " if options[:category]
          RightLinkLog.warn("Received invalid #{category}packet type from queue #{queue} " +
                            "on broker #{@alias}: #{packet.class}")
          nil
        end
      rescue Exception => e
        trace = e.is_a?(Serializer::SerializationError) ? :caller : :trace
        RightLinkLog.error("Failed receiving from queue #{queue} on #{@alias}", e, trace)
        @exceptions.track("receive", e)
        @options[:exception_on_receive_callback].call(message, e) if @options[:exception_on_receive_callback]
        nil
      end
    end

    # Make status updates for connect success
    #
    # === Return
    # true:: Always return true
    def update_success
      @last_failed = false
      @retries = 0
      true
    end

    # Make status updates for connect failure
    #
    # === Return
    # true:: Always return true
    def update_failure
      RightLinkLog.error("Failed to connect to broker #{@alias}")
      if @last_failed
        @retries += 1
      else
        @last_failed = true
        @retries = 0
        @failures.update
      end
      true
    end

    # Delete object from local AMQP cache in case it is no longer consistent with broker
    #
    # === Parameters
    # type(Symbol):: Type of AMQP object
    # name(String):: Name of object
    #
    # === Return
    # true:: Always return true
    def delete_from_cache(type, name)
      @mq.__send__(type == :queue ? :queues : :exchanges).delete(name)
      true
    end

    # Execute packet receive callback, make it a separate method to ease instrumentation
    #
    # === Parameters
    # callback(Proc):: Proc to run
    # args(Array):: Array of pass-through arguments
    #
    # === Return
    # (Object):: Callback return value
    def execute_callback(callback, *args)
      callback.call(*args) if callback
    end

  end # BrokerClient

end # RightScale
