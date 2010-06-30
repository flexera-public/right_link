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

require 'rubygems'

class MQ
  class Queue
    # Asks the broker to redeliver all unacknowledged messages on a
    # specified channel. Zero or more messages may be redelivered.
    #
    # * requeue (default false)
    # If this parameter is false, the message will be redelivered to the original recipient.
    # If this flag is true, the server will attempt to requeue the message, potentially then
    # delivering it to an alternative subscriber.
    #
    def recover(requeue = false)
      @mq.callback{
        @mq.send Protocol::Basic::Recover.new({ :requeue => requeue })
      }
      self
    end
  end
end

# monkey patch to the amqp gem that adds :no_declare => true option for new Queue objects.
# This allows an instance that has no configuration privileges to enroll without blowing
# up the AMQP gem when it tries to subscribe to its queue before it has been created.
# Exchange :no_declare support is already in the eventmachine-0.12.10 gem.
# temporary until we get this into amqp proper
MQ::Queue.class_eval do
  def initialize mq, name, opts = {}
    @mq = mq
    @opts = opts
    @bindings ||= {}
    @mq.queues[@name = name] ||= self
    unless opts[:no_declare]
      @mq.callback{
        @mq.send AMQP::Protocol::Queue::Declare.new({ :queue => name,
                                                      :nowait => true }.merge(opts))
      }
    end
  end
end

begin
  # Horrible evil hack to implement AMQP connection backoff until the AMQP gem contains our patches
  require 'amqp'

  AMQP::Client.module_eval do
    def initialize opts = {}
      @settings = opts
      extend AMQP.client

      @on_disconnect ||= proc{ @connection_status.call(:failed) if @connection_status }

      timeout @settings[:timeout] if @settings[:timeout]
      errback{ @on_disconnect.call } unless @reconnecting

      @connected = false
    end

    def reconnect(force = false)
      if @reconnecting and not force
        # Wait 1 second after first reconnect attempt, in between each subsequent attempt
        EM.add_timer(1) { reconnect(true) }
        return
      end

      unless @reconnecting
        @deferred_status = nil
        initialize(@settings)

        mqs = @channels
        @channels = {}
        mqs.each{ |_,mq| mq.reset } if mqs

        @reconnecting = true
        @reconnect_try = 0
        @reconnect_log = :warn

        again = @settings[:retry]
        again = again.call if again.is_a?(Proc)

        if again.is_a?(Numeric)
          # Retry connection after N seconds
          EM.add_timer(again) { reconnect(true) }
          return
        elsif ![nil, true].include?(again)
          raise ::AMQP::Error, "Could not interpret :retry=>#{again.inspect}; expected nil, true or Numeric"
        end
      end

      if (@reconnect_try % 30) == 0
        RightScale::RightLinkLog.send(@reconnect_log, "Attempting reconnect to broker " +
                                      "#{RightScale::HA_MQ.identity(@settings[:host], @settings[:port])}")
        @reconnect_log = :error if (@reconnect_try % 300) == 0
      end
      @reconnect_try += 1
      log 'reconnecting'
      EM.reconnect(@settings[:host], @settings[:port], self)
    end
  end

  # monkey patch AMQP to clean up @conn when an error is raised after a broker request failure,
  # otherwise AMQP becomes unusable
  AMQP.module_eval do
    def self.start *args, &blk
      begin
        EM.run{
          @conn ||= connect *args
          @conn.callback(&blk) if blk
          @conn
        }
      rescue Exception => e
        @conn = nil
        raise e
      end
    end
  end

rescue LoadError => e
  # Make sure we're dealing with a legitimate missing-file LoadError
  raise e unless e.message =~ /^no such file to load/
  # Missing 'amqp' indicates that the AMQP gem is not installed; we can ignore this
end

module RightScale

  # Manage multiple AMQP broker connections to achieve a high availability service
  class HA_MQ

    STATUS = [
      :connecting,   # Initiated AMQP connection but not yet confirmed that connected
      :connected,    # Confirmed AMQP connection that is declared usable
      :disconnected, # Notified by AMQP that connection has been lost and attempting to reconnect
      :closed,       # AMQP connection closed explicitly or because of too many failed connect attempts
      :failed        # Failed to connect due to internal failure or AMQP failure to connect
    ]

    # Maximum attempts to reconnect a failed connection
    MAX_RECONNECT_ATTEMPTS = 5

    # (Array(Hash)) Priority ordered list of AMQP brokers (exposed only for unit test purposes)
    #   :mq(MQ):: AMQP broker channel
    #   :connection(EM::Connection):: AMQP connection
    #   :identity(String):: Broker identity
    #   :alias(String):: Broker alias used in logs
    #   :status(Symbol):: Status of connection
    #   :tries(Integer):: Number of attempts to reconnect a failed connection
    attr_accessor :brokers

    # Create connections to all configured AMQP brokers
    # The constructed broker list is in priority order
    #
    # === Parameters
    # serializer(Serializer):: Serializer used for marshaling packets being published; if nil,
    #   has same effect as setting options :no_serialize and :no_unserialize
    # options(Hash):: Configuration options:
    #   :user(String):: User name
    #   :pass(String):: Password
    #   :vhost(String):: Virtual host path name
    #   :insist(Boolean):: Whether to suppress redirection of connection
    #   :retry(Integer|Proc):: Number of seconds before try to reconnect or proc returning same
    #   :host{String):: Comma-separated list of AMQP broker host names; if only one, it is reapplied
    #     to successive ports; if none, defaults to localhost; each host may be followed by ':'
    #     and a short string to be used as an alias id; the alias id defaults to the list index,
    #     e.g., "host_a:0, host_c:2"
    #   :port(String|Integer):: Comma-separated list of AMQP broker port numbers corresponding to :host list;
    #     if only one, it is incremented and applied to successive hosts; if none, defaults to AMQP::PORT
    #   :order(Symbol):: Broker selection order when publishing a message: :random or :priority,
    #     defaults to :priority, value can be overridden on publish call
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: If :host and :port are not matched lists
    def initialize(serializer, options = {})
      @options = options
      @connection_status = {}
      @serializer = serializer
      index = -1
      @select = options[:order] || :priority
      @brokers = self.class.addresses(options[:host], options[:port]).map { |a| internal_connect(a, options) }
      @brokers_hash = {}
      @brokers.each { |b| @brokers_hash[b[:identity]] = b }
    end

    # Parse host and port information to form list of broker address information
    #
    # === Parameters
    # host{String):: Comma-separated list of AMQP broker host names; if only one, it is reapplied
    #   to successive ports; if none, defaults to localhost; each host may be followed by ':'
    #   and a short string to be used as an alias id; the alias id defaults to the list index,
    #   e.g., "host_a:0, host_c:2"
    # port(String|Integer):: Comma-separated list of AMQP broker port numbers corresponding to :host list;
    #   if only one, it is incremented and applied to successive hosts; if none, defaults to AMQP::PORT
    #
    # === Returns
    # (Array(Hash)):: List of broker addresses with keys :host, :port, :id
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: If host and port are not matched lists
    def self.addresses(host, port)
      hosts = if host then host.split(/,\s*/) else [ "localhost" ] end
      ports = if port then port.to_s.split(/,\s*/) else [ ::AMQP::PORT ] end
      if hosts.size != ports.size && hosts.size != 1 && ports.size != 1
        raise RightScale::Exceptions::Argument, "Unmatched AMQP host/port lists -- " +
                                                "hosts: #{host.inspect} ports: #{port.inspect}"
      end
      i = -1
      if hosts.size > 1
        hosts.map do |host|
          i += 1
          h = host.split(/:\s*/)
          port = if ports[i] then ports[i].to_i else ports[0].to_i end
          port = port.to_s.split(/:\s*/)[0]
          {:host => h[0], :port => port.to_i, :id => h[1] || i.to_s}
        end
      else
        ports.map do |port|
          i += 1
          p = port.to_s.split(/:\s*/)
          host = if hosts[i] then hosts[i] else hosts[0] end
          host = host.split(/:\s*/)[0]
          {:host => host, :port => p[0].to_i, :id => p[1] || i.to_s}
        end
      end
    end

    # Subscribe an AMQP queue to an AMQP exchange on usable AMQP brokers
    # Handle AMQP message acknowledgement if requested
    # Unserialize received responses and log them as specified
    #
    # === Parameters
    # queue(Hash):: AMQP queue being subscribed with keys :name and :options
    # exchange(Hash|nil):: AMQP exchange to subscribe to with keys :type, :name, and :options,
    #   nil means use empty exchange by directly subscribing to queue
    # options(Hash):: Subscribe options:
    #   :ack(Boolean):: Explicitly acknowledge received messages to AMQP
    #   :no_unserialize(Boolean):: Do not unserialize message, this is an escape for special
    #     situations like enrollment, also implicitly disables receive filtering and logging;
    #     this option is implicitly invoked if initialize without a serializer
    #   :serializer(Any):: Serializer to use for this queue instead of the general purpose one
    #     supplied at initialization
    #   (packet class)(Array(Symbol)):: Filters to be applied in to_s when logging packet to :info,
    #     only packet classes specified are accepted, others are not processed but are logged with error
    #   :category(String):: Packet category description to be used in error messages
    #   :log_data(String):: Additional data to display at end of log entry
    #   :no_log(Boolean):: Disable receive logging
    #
    # === Block
    # Required block is called each time exchange matches a message to the queue
    # Normally it is passed the unserialized packet as its only parameter,
    # which is nil if the received message is not of the right type
    # If :no_unserialize is requested, the two parameters are the broker delivering
    # the message and the unserialized message
    #
    # === Return
    # ids(Array):: Identity of AMQP brokers where successfully subscribed
    def subscribe(queue, exchange = nil, options = {}, &blk)
      to_exchange = " to exchange #{exchange[:name]}" if exchange
      ids = []
      each_usable do |b|
        begin
          RightLinkLog.info("[setup] Subscribing queue #{queue[:name]}#{to_exchange} on broker #{b[:alias]}")
          q = b[:mq].queue(queue[:name], queue[:options] || {})
          if exchange
            x = b[:mq].__send__(exchange[:type], exchange[:name], exchange[:options] || {})
            q = q.bind(x)
          end
          if options[:ack]
            # Ack now before processing to avoid risk of duplication after a crash
            q.subscribe(:ack => true) do |info, msg|
              info.ack
              if options[:no_unserialize] || @serializer.nil?
                blk.call(b, msg)
              else
                blk.call(receive(b, queue[:name], msg, options))
              end
            end
          else
            q.subscribe do |msg|
              if options[:no_unserialize] || @serializer.nil?
                blk.call(b, msg)
              else
                blk.call(receive(b, queue[:name], msg, options))
              end
            end
          end
          ids << b[:identity]
        rescue Exception => e
          RightLinkLog.error("Failed subscribing queue #{queue.inspect}#{to_exchange} on broker #{b[:alias]}: #{e.message}")
        end
      end
      ids
    end

    # Receive message by unserializing it, checking that it an acceptable type, and logging accordingly
    #
    # === Parameters
    # broker(Hash):: Broker that delivered message
    # queue(String):: Name of queue
    # msg(String):: Serialized packet
    # options(Hash):: Subscribe options:
    #   (packet class)(Array(Symbol)):: Filters to be applied in to_s when logging packet to :info,
    #     only packet classes specified are accepted, others are not processed but are logged with error
    #   :category(String):: Packet category description to be used in error messages
    #   :log_data(String):: Additional data to display at end of log entry
    #   :no_log(Boolean):: Disable receive logging unless debug level
    #
    # === Return
    # (Packet|nil):: Unserialized packet or nil if not of right type
    def receive(broker, queue, msg, options = {})
      begin
        packet = @serializer.load(msg)
        if options.key?(packet.class)
          unless options[:no_log] && RightLinkLog.level != :debug
            log_filter = options[packet.class] unless RightLinkLog.level == :debug
            RightLinkLog.__send__(RightLinkLog.level,
              "RECV #{broker[:alias]} #{packet.to_s(log_filter)} #{options[:log_data]}")
          end
          packet
        else
          category = options[:category] + " " if options[:category]
          RightLinkLog.warn("RECV #{broker[:alias]} - Invalid #{category}packet type: #{packet.class}")
          nil
        end
      rescue Exception => e
        RightLinkLog.error("RECV #{broker[:alias]} - Failed receiving from queue #{queue}: #{e.message}")
        raise e
      end
    end

    # Publish packet to AMQP exchange of first usable broker, or all usable brokers
    # if fanout requested
    #
    # === Parameters
    # exchange(Hash):: AMQP exchange to subscribe to with keys :type, :name, and :options
    # packet(Packet):: Packet to serialize and publish
    # options(Hash):: Publish options -- standard AMQP ones plus
    #   :fanout(Boolean):: true means publish to all allowed usable brokers
    #   :brokers(Array):: Identity of brokers allowed to use, defaults to all if nil or empty
    #   :order(Symbol):: Broker selection order: :random or :priority,
    #     defaults to @select if :brokers is nil, otherwise defaults to :priority
    #   :no_serialize(Boolean):: Do not serialize packet because it is already serialized,
    #     this is an escape for special situations like enrollment, also implicitly disables
    #     publish logging; this option is implicitly invoked if initialize without a serializer
    #   :log_filter(Array(Symbol)):: Filters to be applied in to_s when logging packet to :info
    #   :log_data(String):: Additional data to display at end of log entry
    #   :no_log(Boolean):: Disable publish logging unless debug level
    #
    # === Return
    # ids(Array):: Identity of AMQP brokers where packet was successfully published
    #
    # === Raise
    # (RightScale::Exceptions::IO):: If cannot find a usable AMQP broker connection
    def publish(exchange, packet, options = {})
      ids = []
      msg = if options[:no_serialize] || @serializer.nil? then packet else @serializer.dump(packet) end
      use(options).each do |b|
        if b[:status] == :connected
          begin
            unless (options[:no_log] && RightLinkLog.level != :debug) || options[:no_serialize] || @serializer.nil?
              re = "RE" if packet.respond_to?(:tries) && !packet.tries.empty?
              log_filter = options[:log_filter] unless RightLinkLog.level == :debug
              RightLinkLog.__send__(RightLinkLog.level,
                "#{re}SEND #{b[:alias]} #{packet.to_s(log_filter)} #{options[:log_data]}")
            end
            b[:mq].__send__(exchange[:type], exchange[:name], exchange[:options] || {}).publish(msg, options)
            ids << b[:identity]
            break unless options[:fanout]
          rescue Exception => e
            RightLinkLog.error("#{re}SEND #{b[:alias]} - Failed publishing to exchange #{exchange.inspect}: #{e.message}")
          end
        end
      end
      if ids.empty?
        allowed = "the allowed " if options[:brokers]
        count = (options[:brokers].size if options[:brokers]) || @brokers.size
        raise RightScale::Exceptions::IO, "None of #{allowed}#{count} broker connections are usable"
      end
      ids
    end

    # Delete queue in all usable brokers
    #
    # === Parameters
    # name(String):: Queue name
    #
    # === Return
    # ids(Array):: Identity of AMQP brokers where queue was deleted
    def delete(name)
      ids = []
      each_usable do |b|
        begin
          b[:mq].queue(name).delete
          ids << b[:identity]
        rescue Exception => e
          RightLinkLog.error("Failed deleting queue #{name.inspect} on broker #{b[:alias]}: #{e.message}")
        end
      end
      ids
    end

    # Convert broker identities to aliases
    #
    # === Parameters
    # identities(Array):: Broker identities with or without nanite prefix
    #
    # === Return
    # (Array):: Broker aliases
    def aliases(identities)
      identities.map { |i| alias_(i) }
    end

    # Convert broker identity to its alias
    #
    # === Parameters
    # identity(String):: Broker identity with or without nanite prefix
    #
    # === Return
    # (String|nil):: Broker alias, or nil if not a known broker
    def alias_(identity)
      (@brokers_hash[identity] || @brokers_hash[AgentIdentity.serialized_from_nanite(identity)])[:alias] rescue nil
    end

    # Convert broker identity to its id used in alias
    #
    # === Parameters
    # identity(String):: Broker identity with or without nanite prefix
    #
    # === Return
    # (Integer|nil):: Broker alias ia, or nil if not a known broker
    def id_(identity)
      alias_(identity)[1..-1].to_i rescue nil
    end

    # Find broker with given alias id
    #
    # === Parameters
    # id(Integer):: Broker alias id
    #
    # === Return
    # (Hash|nil):: Broker if found, otherwise nil
    def find(id)
      each { |b| return b if b[:alias][1..-1].to_i == id } if id
      nil
    end

    # Parse host and port information to form list of broker identities
    #
    # === Parameters
    # host{String):: Comma-separated list of AMQP broker host names; if only one, it is reapplied
    #   to successive ports; if none, defaults to localhost; each host may be followed by ':'
    #   and a short string to be used as an alias id; the alias id defaults to the list index,
    #   e.g., "host_a:0, host_c:2"
    # port(String|Integer):: Comma-separated list of AMQP broker port numbers corresponding to :host list;
    #   if only one, it is incremented and applied to successive hosts; if none, defaults to AMQP::PORT
    #
    # === Returns
    # (Array):: Identity of each broker
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: If host and port are not matched lists
    def self.identities(host, port)
      addresses(host, port).map { |a| identity(a[:host], a[:port]) }
    end

    # Construct a broker identity from its host and port of the form
    # rs-broker-host-port, with any '-'s in host replaced by '~'
    #
    # === Parameters
    # host{String):: IP host name or address for individual broker
    # port(Integer):: TCP port number for individual broker
    #
    # === Returns
    # (String):: Unique broker identity
    def self.identity(host, port)
      AgentIdentity.new('rs', 'broker', port.to_i, host.gsub('-', '~')).to_s
    end

    # Extract host name from broker identity
    #
    # === Parameters
    # identity{String):: Broker identity
    #
    # === Returns
    # (String):: IP host name
    def self.host(identity)
      AgentIdentity.parse(identity).token.gsub('~', '-')
    end

    # Extract port number from broker identity
    #
    # === Parameters
    # identity{String):: Broker identity
    #
    # === Returns
    # (Integer):: TCP port number
    def self.port(identity)
      AgentIdentity.parse(identity).base_id
    end

    # Form string of hosts and associated ids
    #
    # === Return
    # (String):: Comma separated list of host:id
    def hosts
      @brokers.map { |b| "#{self.class.host(b[:identity])}:#{b[:alias][1..-1]}" }.join(",")
    end

    # Form string of hosts and associated ids
    #
    # === Return
    # (String):: Comma separated list of host:id
    def ports
      @brokers.map { |b| "#{self.class.port(b[:identity])}:#{b[:alias][1..-1]}" }.join(",")
    end

    # Iterate over AMQP broker connections
    #
    # === Block
    # Required block to which each AMQP broker connection is passed
    def each
      @brokers.each { |b| yield b }
    end

    # Iterate over usable AMQP broker connections
    #
    # === Block
    # Required block to which each AMQP broker connection is passed
    def each_usable
      @brokers.each { |b| yield b if b[:status] == :connected }
    end

    # Get identity of usable AMQP brokers
    #
    # === Return
    # (Array):: Identity of usable brokers
    def usable
      @brokers.inject([]) { |c, b| if b[:status] == :connected then c << b[:identity] else c end }
    end

    # Get identity of failed AMQP brokers, i.e., ones that were never successfully connected,
    # not ones that are just disconnected
    #
    # === Return
    # (Array):: Identity of failed brokers
    def failed
      @brokers.inject([]) { |c, b| if b[:status] == :failed then c << b[:identity] else c end }
    end

    # Set prefetch value for each AMQP broker
    #
    # === Parameters
    # value(Integer):: Maximum number of messages the AMQP broker is to prefetch
    #   before it receives an ack. Value 1 ensures that only last unacknowledged
    #   gets redelivered if the broker crashes. Value 0 means unlimited prefetch.
    #
    # === Return
    # true:: Always return true
    def prefetch(value)
      each_usable { |b| b[:mq].prefetch(value) }
      true
    end

    # Make new connection to broker at specified address unless already connected
    #
    # === Parameters
    # host{String):: IP host name or address for individual broker
    # port(Integer):: TCP port number for individual broker
    # id(Integer):: Small unique id associated with this broker for use in forming alias
    # priority(Integer|nil):: Priority position of this broker in list for use
    #   by this agent with nil meaning add to end of list
    #
    # === Block
    # Optional block is executed after initiating the connection unless already
    # connected to this broker, only block argument is the broker hash
    #
    # === Return
    # broker(Hash):: Broker for which connection initiated
    #
    # === Raise
    # Exception:: If exceed maximum attempts to reconnect
    # Exception:: If host and port do not match an existing broker but id does
    # Exception:: If requested priority position would leave a gap in the list
    def connect(host, port, id, priority = nil, &blk)
      broker = nil
      identity = self.class.identity(host, port)
      existing = @brokers_hash[identity]
      if existing && existing[:status] == :connected
        RightLinkLog.info("Ignoring request to reconnect #{identity} because already connected")
      elsif existing && existing[:tries] >= MAX_RECONNECT_ATTEMPTS
        existing[:status] = :closed
        raise Exception, "Exceeded maximum of #{MAX_RECONNECT_ATTEMPTS} attempts to reconnect to #{identity}, closing broker"
      elsif !existing && b = find(id)
        raise Exception, "Not allowed to change host or port of existing broker #{b[:identity]}, " +
                         "alias b#{id}, to #{host} and #{port.inspect}"
      else
        broker = internal_connect({:host => host, :port => port, :id => id}, @options)
        broker[:tries] = existing[:tries] + 1 if existing && broker[:status] == :failed
        i = 0; @brokers.each { |b| break if b[:identity] == identity; i += 1 }
        if priority && priority < i
          @brokers.insert(priority, broker)
        elsif priority && priority > i
          if connection_closable(broker)
            broker[:status] = :closed
            broker[:connection].close
          end
          raise Exception, "Requested priority position #{priority} for #{identity} " +
                           "would leave gap in broker list of size #{@brokers.size}"
        elsif connection_closable(@brokers[i])
          @brokers[i][:status] = :closed
          @brokers[i][:connection].close
          @brokers[i] = broker
        else
          @brokers[i] = broker
        end
        @brokers_hash[identity] = broker
        yield broker if block_given?
      end
      broker
    end

    # Store block to be called when there is a change in connection status
    # Each call to this method stores another block
    #
    # === Parameters
    # options(Hash):: Connection status monitoring options
    #   :one_off(Integer):: Seconds to wait for status change; only send update once;
    #     if timeout, report :timeout as the status
    #   :boundary(Symbol):: :any if only report change on any (0/1) boundary,
    #     :all if only report change on all (n-1/n) boundary, defaults to :any
    #   :brokers(Array):: Only report a status change for these identified brokers
    #
    # === Block
    # Block to be called when usable connection count crosses a status boundary
    #
    # === Return
    # id(String):: Identifier associated with connection status request
    def connection_status(options = {}, &blk)
      id = AgentIdentity.generate
      @connection_status[id] = {:boundary => options[:boundary], :brokers => brokers, :block => blk}
      if timeout = options[:one_off]
        @connection_status[id][:timer] = EM::Timer.new(timeout) do
          if @connection_status[id]
            @connection_status[id][:block].call(:timeout)
            @connection_status.delete(id)
          end
        end
      end
      id
    end

    # Determine whether broker is in a state to have a connection to be closed
    #
    # === Parameters
    # broker(Hash):: Broker to be tested
    #
    # === Return
    # (Boolean):: true if can close, otherwise false
    def connection_closable(broker)
      ![:closed, :failed].include?(broker[:status]) if broker
    end

    # Close all AMQP broker connections
    #
    # === Block
    # Optional block to be executed after all connections are closed
    def close(&blk)
      handler = CloseHandler.new(@brokers.size)
      handler.callback { blk.call if blk }

      @brokers.each do |b|
        if connection_closable(b)
          begin
            b[:connection].close { b[:status] = :closed; handler.close_one }
          rescue Exception => e
            RightLinkLog.error("Failed to close broker #{b[:alias]}: #{e.message}")
            b[:status] = :closed
            handler.close_one
          end
        else
          handler.close_one
        end
      end
    end

    protected

    # Helper for deferring close action until all AMQP connections are closed
    class CloseHandler

      include EM::Deferrable

      def initialize(count)
        @count = count
        @closed = 0
      end

      def close_one
        @closed += 1
        succeed if @closed == @count
      end

    end

    # Make AMQP broker connection and register for status updates
    #
    # === Parameters
    # address(Hash):: Broker address
    #   :host(String:: IP host name or address
    #   :port(Integer):: TCP port number for individual broker
    #   :id(String):: Small id associated with this broker for use in forming alias
    # options(Hash):: Options required to create an AMQP connection other than :host and :port
    #
    # === Return
    # broker(Hash):: AMQP broker
    def internal_connect(address, options)
      broker = {
        :mq => nil,
        :connection => nil,
        :identity => self.class.identity(address[:host], address[:port]),
        :alias => "b#{address[:id]}",
        :status => :connecting,
        :tries => 0
      }
      begin
        RightLinkLog.info("[setup] Connecting to broker #{broker[:identity]}, alias #{broker[:alias]}")
        broker[:connection] = AMQP.connect(:user => options[:user],
                                           :pass => options[:pass],
                                           :vhost => options[:vhost],
                                           :host => address[:host],
                                           :port => address[:port],
                                           :insist => options[:insist] || false,
                                           :retry => options[:retry] || 15)
        broker[:mq] = MQ.new(broker[:connection])
        broker[:mq].__send__(:connection).connection_status { |status| update_status(broker, status) }
      rescue Exception => e
        broker[:status] = :failed
        RightLinkLog.error("Failed connecting to #{broker[:alias]}: #{e.message}")
        broker[:connection].close if broker[:connection]
      end
      broker
    end

    # Callback from AMQP with connection status
    #
    # === Parameters
    # broker(Hash):: AMQP broker reporting status
    # status(Symbol):: Status of connection (:connected, :disconnected, :failed)
    #
    # === Return
    # true:: Always return true
    def update_status(broker, status)
      before = usable
      broker[:status] = status
      after = usable
      if status == :failed
        RightLinkLog.error("Failed to connect to broker #{broker[:alias]}")
      end
      unless before == after
        RightLinkLog.info("[status] Broker #{broker[:alias]} is now #{status}, usable brokers: [#{aliases(after).join(", ")}]")
      end
      @connection_status.reject! do |k, v|
        reject = false
        unless v[:brokers].nil? || v[:brokers].include?(broker[:idenitity])
          update = if v[:boundary] == :all
            max = @brokers.size
            if before.size < max && after.size == max
              :connected
            elsif before.size == max && after.size < max
              :disconnected
            end
          else
            if before.size == 0 && after.size > 0
              :connected
            elsif before.size > 0 && after.size == 0
              :disconnected
            end
          end
          if update
            v[:block].call(update)
            if v[:timer]
              v[:timer].cancel
              reject = true
            end
          end
        end
        reject
      end
      true
    end

    # Select the brokers to be used in the desired order
    #
    # === Parameters
    # options(Hash):: Selection options:
    #   :brokers(Array):: Identity of brokers allowed to use, defaults to all if nil or empty
    #   :order(Symbol):: Broker selection order: :random or :priority,
    #     defaults to @select if :brokers is nil, otherwise defaults to :priority
    #
    # === Return
    # (Array):: Allowed brokers in the order to be used
    def use(options)
      choices, select = if options[:brokers] && !options[:brokers].empty?
        [options[:brokers].map { |a| @brokers_hash[a] }, options[:order]]
      else
        [@brokers, (options[:order] || @select)]
      end
      if select == :random
        choices.sort_by { rand }
      else
        choices
      end
    end

  end # HA_MQ

end # RightScale