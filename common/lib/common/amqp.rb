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

  # May raise a MQ::Error exception when the frame payload contains a
  # Protocol::Channel::Close object.
  #
  # This usually occurs when a client attempts to perform an illegal
  # operation. A short, and incomplete, list of potential illegal operations
  # follows:
  # * publish a message to a deleted exchange (NOT_FOUND)
  # * declare an exchange using the reserved 'amq.' naming structure (ACCESS_REFUSED)
  #
  def process_frame frame
    log :received, frame

    case frame
    when Frame::Header
      @header = frame.payload
      @body = ''

    when Frame::Body
      @body << frame.payload
      if @body.length >= @header.size
        if @method.is_a? Protocol::Basic::Return
          @on_return_message.call @method, @body if @on_return_message
        else
          @header.properties.update(@method.arguments)
          @consumer.receive @header, @body if @consumer
        end
        @body = @header = @consumer = @method = nil
      end

    when Frame::Method
      case method = frame.payload
      when Protocol::Channel::OpenOk
        send Protocol::Access::Request.new(:realm => '/data',
                                           :read => true,
                                           :write => true,
                                           :active => true,
                                           :passive => true)

      when Protocol::Access::RequestOk
        @ticket = method.ticket
        callback{
          send Protocol::Channel::Close.new(:reply_code => 200,
                                            :reply_text => 'bye',
                                            :method_id => 0,
                                            :class_id => 0)
        } if @closing
        succeed

      when Protocol::Basic::CancelOk
        if @consumer = consumers[ method.consumer_tag ]
          @consumer.cancelled
        else
          MQ.error "Basic.CancelOk for invalid consumer tag: #{method.consumer_tag}"
        end

      when Protocol::Queue::DeclareOk
        queues[ method.queue ].receive_status method

      when Protocol::Basic::Deliver, Protocol::Basic::GetOk
        @method = method
        @header = nil
        @body = ''

        if method.is_a? Protocol::Basic::GetOk
          @consumer = get_queue{|q| q.shift }
          MQ.error "No pending Basic.GetOk requests" unless @consumer
        else
          @consumer = consumers[ method.consumer_tag ]
          MQ.error "Basic.Deliver for invalid consumer tag: #{method.consumer_tag}" unless @consumer
        end

      when Protocol::Basic::GetEmpty
        if @consumer = get_queue{|q| q.shift }
          @consumer.receive nil, nil
        else
          MQ.error "Basic.GetEmpty for invalid consumer"
        end

      when Protocol::Basic::Return
        @method = method
        @header = nil
        @body = ''

      when Protocol::Channel::Close
        raise Error, "#{method.reply_text} in #{Protocol.classes[method.class_id].methods[method.method_id]} on #{@channel}"

      when Protocol::Channel::CloseOk
        @closing = false
        conn.callback{ |c|
          c.channels.delete @channel
          c.close if c.channels.empty?
        }

      when Protocol::Basic::ConsumeOk
        if @consumer = consumers[ method.consumer_tag ]
          @consumer.confirm_subscribe
        else
          MQ.error "Basic.ConsumeOk for invalid consumer tag: #{method.consumer_tag}"
        end
      end
    end
  end

  # Provide callback to be activated when a message is returned
  def return_message(&blk)
    @on_return_message = blk
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
          "#{RightScale::AgentIdentity.new('rs', 'broker', @settings[:port].to_i, @settings[:host].gsub('-', '~')).to_s}")
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

  # This monkey patch catches exceptions that would otherwise cause EM to stop or be in a bad
  # state if a top level EM error handler was setup. Instead close the connection and leave EM
  # alone.
  # Don't log an error if the environment variable IGNORE_AMQP_FAILURES is set (used in the 
  # enroll script)
  AMQP::Client.module_eval do
    alias :orig_receive_data :receive_data
    def receive_data(*args)
      begin
        orig_receive_data(*args)
      rescue Exception => e
        RightScale::RightLinkLog.error("Exception caught while processing AMQP frame: #{e.message}, closing connection.") unless ENV['IGNORE_AMQP_FAILURES']
        close_connection
      end
    end
  end

  # Add a new callback to amqp gem that triggers once the handshake with the broker completed
  # The 'connected' status callback happens before the handshake is done and if it results in
  # a lot of activity it might prevent EM from being able to call the code handling the
  # incoming handshake packet in a timely fashion causing the broker to close the connection
  AMQP::BasicClient.module_eval do
    alias :orig_process_frame :process_frame
    def process_frame(frame)
      orig_process_frame(frame)
      @connection_status.call(:ready) if @connection_status && frame.payload.is_a?(AMQP::Protocol::Connection::Start)
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

    class NoConnectedBrokers < Exception; end

    # Maximum number of times the failed? function would be called for a failed broker without
    # returning true
    MAX_FAILED_BACKOFF = 20

    STATUS = [
      :connecting,   # Initiated AMQP connection but not yet confirmed that connected
      :connected,    # Confirmed AMQP connection
      :disconnected, # Notified by AMQP that connection has been lost and attempting to reconnect
      :closed,       # AMQP connection closed explicitly or because of too many failed connect attempts
      :failed        # Failed to connect due to internal failure or AMQP failure to connect
    ]

    # (Array(Hash)) Priority ordered list of AMQP brokers (exposed only for unit test purposes)
    #   :mq(MQ):: AMQP broker channel
    #   :connection(EM::Connection):: AMQP connection
    #   :identity(String):: Broker identity
    #   :alias(String):: Broker alias used in logs
    #   :status(Symbol):: Status of connection
    #   :tries(Integer):: Number of attempts to reconnect a failed connection
    #   :backoff(Integer):: Number of times should ignore failed query for given broker in order
    #     to achieve exponential backoff on connect attempts when failed
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
    # ArgumentError:: If :host and :port are not matched lists
    def initialize(serializer, options = {})
      @options = options
      @connection_status = {}
      @serializer = serializer
      index = -1
      @select = options[:order] || :priority
      @brokers = self.class.addresses(options[:host], options[:port]).map { |a| internal_connect(a, options) }
      @closed = false
      @brokers_hash = {}
      @brokers.each { |b| @brokers_hash[b[:identity]] = b }
    end

    # Subscribe an AMQP queue to an AMQP exchange on all brokers that are connected or still connecting
    # Allow connecting here because subscribing may happen before all have confirmed connected
    # Do not wait for confirmation from broker that subscription is complete
    # When a message is received, acknowledge, unserialize, and log it as specified
    # If the message is unserialized and it is not of the right type, it is dropped after logging a warning
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
    #   :no_log(Boolean):: Disable receive logging unless debug level
    #   :exchange2(Hash):: Additional exchange to which same queue is to be bound
    #   :brokers(Array):: Identity of brokers for which to subscribe, defaults to all usable if nil or empty
    #
    # === Block
    # Block with following parameters to be called each time exchange matches a message to the queue:
    #   identity(String):: Identity of broker delivering the message
    #   message(Packet|String):: Message received, which is unserialized unless :no_unserialize was specified
    #
    # === Return
    # identities(Array):: Identity of brokers where successfully subscribed
    def subscribe(queue, exchange = nil, options = {}, &blk)
      to_exchange =  if exchange
        if options[:exchange2]
          " to exchanges #{exchange[:name]} and #{options[:exchange2][:name]}"
        else
          " to exchange #{exchange[:name]}"
        end
      end
      identities = []
      each_usable(options[:brokers]) do |b|
        begin
          RightLinkLog.info("[setup] Subscribing queue #{queue[:name]}#{to_exchange} on broker #{b[:alias]}")
          q = b[:mq].queue(queue[:name], queue[:options] || {})
          b[:queues] << q
          if exchange
            x = b[:mq].__send__(exchange[:type], exchange[:name], exchange[:options] || {})
            binding = q.bind(x)
            if exchange2 = options[:exchange2]
              q.bind(b[:mq].__send__(exchange2[:type], exchange2[:name], exchange2[:options] || {}))
            end
            q = binding
          end
          if options[:ack]
            q.subscribe(:ack => true) do |info, msg|
              begin
                # Ack now before processing to avoid risk of duplication after a crash
                info.ack
                if options[:no_unserialize] || @serializer.nil?
                  blk.call(b[:identity], msg)
                elsif msg == "nil"
                  # This happens as part of connecting an instance agent to a broker
                  RightLinkLog.debug("RECV #{b[:alias]} nil message ignored")
                elsif
                  packet = receive(b, queue[:name], msg, options)
                  blk.call(b[:identity], packet) if packet
                end
              rescue Exception => e
                RightLinkLog.error("Failed executing block for message from queue #{queue.inspect}#{to_exchange} " +
                                   "on broker #{b[:alias]}: #{e.message}\n" + e.backtrace.join("\n"))
              end
            end
          else
            q.subscribe do |msg|
              begin
                if options[:no_unserialize] || @serializer.nil?
                  blk.call(b[:identity], msg)
                elsif msg == "nil"
                  # This happens as part of connecting an instance agent to a broker
                  RightLinkLog.debug("RECV #{b[:alias]} nil message ignored")
                elsif
                  packet = receive(b, queue[:name], msg, options)
                  blk.call(b[:identity], packet) if packet
                end
              rescue Exception => e
                RightLinkLog.error("Failed executing block for message from queue #{queue.inspect}#{to_exchange} " +
                                   "on broker #{b[:alias]}: #{e.message}\n" + e.backtrace.join("\n"))
              end
            end
          end
          identities << b[:identity]
        rescue Exception => e
          RightLinkLog.error("Failed subscribing queue #{queue.inspect}#{to_exchange} on broker #{b[:alias]}: #{e.message}")
        end
      end
      identities
    end

    # Unsubscribe from the specified queues on usable brokers
    # Silently ignore unknown queues
    #
    # === Parameters
    # queue_names(Array):: Names of queues previously subscribed to
    # timeout(Integer):: Number of seconds to wait for all confirmations, defaults to no timeout
    #
    # === Block
    # Optional block with no parameters to be called after all queues are unsubscribed
    #
    # === Return
    # true:: Always return true
    def unsubscribe(queue_names, timeout = nil, &blk)
      count = each_usable.inject(0) do |c, b|
        c + b[:queues].inject(0) { |c, q| c + (queue_names.include?(q.name) ? 1 : 0) }
      end
      if count == 0
        blk.call if blk
      else
        handler = CountedDeferrable.new(count, timeout)
        handler.callback { blk.call if blk }
        each_usable do |b|
          b[:queues].each do |q|
            if queue_names.include?(q.name)
              begin
                RightLinkLog.info("[stop] Unsubscribing queue #{q.name} on broker #{b[:alias]}")
                q.unsubscribe { handler.completed_one }
              rescue Exception => e
                RightLinkLog.error("Failed unsubscribing queue #{q.name} on broker #{b[:alias]}: #{e.message}")
                handler.completed_one
              end
            end
          end
        end
      end
      true
    end

    # Declare queue or exchange object but do not subscribe to it
    #
    # === Parameters
    # type(Symbol):: Type of object: :queue or :exchange
    # name(String):: Name of object
    # options(Hash):: Declare options
    #
    # === Return
    # identities(Array):: Identity of brokers where successfully declared
    def declare(type, name, options = {})
      each_usable(options[:brokers]) do |b|
        begin
          RightLinkLog.info("[setup] Declaring #{type.to_s} #{name} on broker #{b[:alias]}")
          b[:mq].__send__(type, name, options)
        rescue Exception => e
          RightLinkLog.error("Failed declaring #{type.to_s} #{name} on broker #{b[:alias]}: #{e.message}")
        end
      end
      true
    end

    # Publish message to AMQP exchange of first connected broker, or all connected brokers
    # if fanout requested
    #
    # === Parameters
    # exchange(Hash):: AMQP exchange to subscribe to with keys :type, :name, and :options
    # packet(Packet):: Message to serialize and publish
    # options(Hash):: Publish options -- standard AMQP ones plus
    #   :fanout(Boolean):: true means publish to all connected brokers
    #   :brokers(Array):: Identity of brokers selected for use, defaults to all if nil or empty
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
    # identities(Array):: Identity of brokers where packet was successfully published
    #
    # === Raise
    # NoConnectedBrokers:: If cannot find a connected broker
    def publish(exchange, packet, options = {})
      identities = []
      msg = if options[:no_serialize] || @serializer.nil? then packet else @serializer.dump(packet) end
      brokers = use(options)
      brokers.each do |b|
        if b[:status] == :connected
          begin
            unless (options[:no_log] && RightLinkLog.level != :debug) || options[:no_serialize] || @serializer.nil?
              re = "RE-" if packet.respond_to?(:tries) && !packet.tries.empty?
              log_filter = options[:log_filter] unless RightLinkLog.level == :debug
              RightLinkLog.info("#{re}SEND #{b[:alias]} #{packet.to_s(log_filter)} #{options[:log_data]}")
            end
            RightLinkLog.debug("... publish options #{options.inspect}, exchange #{exchange[:name]}, " +
                               "type #{exchange[:type]}, options #{exchange[:options].inspect}")
            b[:mq].__send__(exchange[:type], exchange[:name], exchange[:options] || {}).publish(msg, options)
            identities << b[:identity]
            break unless options[:fanout]
          rescue Exception => e
            RightLinkLog.error("#{re}SEND #{b[:alias]} - Failed publishing to exchange #{exchange.inspect}: #{e.message}")
          end
        end
      end
      if identities.empty?
        selected = "selected " if options[:brokers]
        list = aliases(brokers.map { |b| b[:identity] }).join(", ")
        raise NoConnectedBrokers, "None of #{selected}brokers [#{list}] are usable for publishing"
      end
      identities
    end

    # Delete queue in all usable brokers
    #
    # === Parameters
    # name(String):: Queue name
    # options(Hash):: Queue declare options
    #
    # === Return
    # identities(Array):: Identity of brokers where queue was deleted
    def delete(name, options = {})
      identities = []
      each_usable do |b|
        begin
          b[:mq].queue(name, options).delete
          identities << b[:identity]
        rescue Exception => e
          RightLinkLog.error("Failed deleting queue #{name.inspect} on broker #{b[:alias]}: #{e.message}")
        end
      end
      identities
    end

    # Parse host and port information to form list of broker address information
    #
    # === Parameters
    # host{String):: Comma-separated list of broker host names; if only one, it is reapplied
    #   to successive ports; if none, defaults to localhost; each host may be followed by ':'
    #   and a short string to be used as an alias id; the alias id defaults to the list index,
    #   e.g., "host_a:0, host_c:2"
    # port(String|Integer):: Comma-separated list of broker port numbers corresponding to :host list;
    #   if only one, it is incremented and applied to successive hosts; if none, defaults to AMQP::PORT
    #
    # === Returns
    # (Array(Hash)):: List of broker addresses with keys :host, :port, :id
    #
    # === Raise
    # ArgumentError:: If host and port are not matched lists
    def self.addresses(host, port)
      hosts = if host then host.split(/,\s*/) else [ "localhost" ] end
      ports = if port then port.to_s.split(/,\s*/) else [ ::AMQP::PORT ] end
      if hosts.size != ports.size && hosts.size != 1 && ports.size != 1
        raise ArgumentError.new("Unmatched AMQP host/port lists -- hosts: #{host.inspect} ports: #{port.inspect}")
      end
      i = -1
      if hosts.size > 1
        hosts.map do |host|
          i += 1
          h = host.split(/:\s*/)
          port = if ports[i] then ports[i].to_i else ports[0].to_i end
          port = port.to_s.split(/:\s*/)[0]
          {:host => h[0], :port => port.to_i, :id => (h[1] || i.to_s).to_i}
        end
      else
        ports.map do |port|
          i += 1
          p = port.to_s.split(/:\s*/)
          host = if hosts[i] then hosts[i] else hosts[0] end
          host = host.split(/:\s*/)[0]
          {:host => host, :port => p[0].to_i, :id => (p[1] || i.to_s).to_i}
        end
      end
    end
 
    # Parse host and port information to form list of broker identities
    #
    # === Parameters
    # host{String):: Comma-separated list of broker host names; if only one, it is reapplied
    #   to successive ports; if none, defaults to localhost; each host may be followed by ':'
    #   and a short string to be used as an alias id; the alias id defaults to the list index,
    #   e.g., "host_a:0, host_c:2"
    # port(String|Integer):: Comma-separated list of broker port numbers corresponding to :host list;
    #   if only one, it is incremented and applied to successive hosts; if none, defaults to AMQP::PORT
    #
    # === Returns
    # (Array):: Identity of each broker
    #
    # === Raise
    # ArgumentError:: If host and port are not matched lists
    def self.identities(host, port = nil)
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

    # Break broker identity down into individual parts if exists
    #
    # === Parameters
    # id(Integer|String):: Broker alias, alias id, or identity with or without nanite prefix
    #
    # === Return
    # (Array):: Host, port, id, priority; all nil if broker not found
    def identity_parts(id)
      if id && identity = get(id)
        priority = 0
        @brokers.each { |b| break if b[:identity] == identity; priority += 1 }
        [host(identity), port(identity), alias_(identity)[1..-1].to_i, priority]
      else
        [nil, nil, nil, nil]
      end
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
      identity = AgentIdentity.parse(identity).to_s rescue nil
      @brokers_hash[identity][:alias] rescue nil
    end

    # Form string of hosts and associated ids
    #
    # === Return
    # (String):: Comma separated list of host:id
    def hosts
      @brokers.map { |b| "#{host(b[:identity])}:#{b[:alias][1..-1]}" }.join(",")
    end

    # Form string of hosts and associated ids
    #
    # === Return
    # (String):: Comma separated list of host:id
    def ports
      @brokers.map { |b| "#{port(b[:identity])}:#{b[:alias][1..-1]}" }.join(",")
    end

    # Get broker identity if exists
    #
    # === Parameters
    # id(Integer|String):: Broker alias, alias id, or identity with or without nanite prefix
    #
    # === Return
    # (String|nil):: Broker identity if found, otherwise nil
    def get(id)
      @brokers.each do |b|
        if b[:identity] == id || b[:alias] == id || b[:alias][1..-1].to_i == id ||
           b[:identity] == (AgentIdentity.parse(id).to_s rescue nil)
          return b[:identity]
        end
      end if id
      nil
    end

    # Check whether broker is connected
    #
    # === Parameters
    # identity{String):: Broker identity
    #
    # === Return
    # (Boolean):: true if broker status is :connect, otherwise false, or nil if broker unknown
    def connected?(identity)
      @brokers_hash[identity][:status] == :connected rescue nil
    end

    # Get identity of connected brokers
    #
    # === Return
    # (Array):: Identity of connected brokers
    def connected
      @brokers.inject([]) { |c, b| if b[:status] == :connected then c << b[:identity] else c end }
    end

    # Get identity of usable brokers
    #
    # === Return
    # (Array):: Identity of usable brokers
    def usable
      each_usable.map { |b| b[:identity] }
    end

    # Get identity of unusable brokers
    #
    # === Return
    # (Array):: Identity of unusable brokers
    def unusable
      @brokers.map { |b| b[:identity] } - each_usable.map { |b| b[:identity] }
    end

    # Get identity of all brokers
    #
    # === Return
    # (Array):: Identity of all brokers
    def all
      @brokers.map { |b| b[:identity] }
    end

    # Get identity of failed brokers, i.e., ones that were never successfully connected,
    # not ones that are just disconnected
    #
    # backoff(Boolean):: Whether to adjust response based on the number of attempts
    #   to reconnect, i.e., after the first connect attempt for a failed connection
    #   only include it in the failed list every b[:tries]**2 times, up to the
    #   MAX_FAILED_BACKOFF limit, e.g., after 4 tries a failed broker would only
    #   be included after 16 additional requests; defaults to false
    #
    # === Return
    # (Array):: Identity of failed brokers
    def failed(backoff = false)
      @brokers.inject([]) { |c, b| if failed?(b, backoff) then c << b[:identity] else c end }
    end

    # Check whether broker is failed
    # Apply exponential backoff algorithm if requested
    #
    # === Parameters
    # broker(Hash):: Broker attributes
    # backoff(Boolean):: Whether to apply backoff algorithm
    #
    # === Return
    # (Boolean):: Whether considered failed
    def failed?(broker, backoff = false)
      if backoff
        broker[:status] == :failed && (broker[:backoff] -= 1) <= 0
      else
        broker[:status] == :failed
      end
    end

    # Set prefetch value for each usable broker
    #
    # === Parameters
    # value(Integer):: Maximum number of messages the broker is to prefetch
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
    # or currently connecting
    #
    # === Parameters
    # host{String):: IP host name or address for individual broker
    # port(Integer):: TCP port number for individual broker
    # alias_id(Integer):: Small unique id associated with this broker for use in forming alias
    # priority(Integer|nil):: Priority position of this broker in list for use
    #   by this agent with nil meaning add to end of list
    # force(Boolean):: Reconnect even if already connected
    #
    # === Block
    # Optional block with following parameters to be called after initiating the connection
    # unless already connected to this broker:
    #   identity(String):: Broker identity
    #
    # === Return
    # (Boolean):: true if connected, false if no connect attempt made
    #
    # === Raise
    # Exception:: If host and port do not match an existing broker but alias id does
    # Exception:: If requested priority position would leave a gap in the list
    def connect(host, port, alias_id, priority = nil, force = false, &blk)
      identity = self.class.identity(host, port)
      existing = @brokers_hash[identity]
      if existing && [:connected, :connecting].include?(existing[:status]) && !force
        RightLinkLog.info("Ignored request to reconnect #{identity} because already #{existing[:status].to_s}")
        false
      elsif !existing && identity = get(alias_id)
        raise Exception, "Not allowed to change host or port of existing broker #{identity}, " +
                         "alias b#{alias_id}, to #{host} and #{port.inspect}"
      else
        broker = internal_connect({:host => host, :port => port, :id => alias_id}, @options)
        if existing && broker[:status] == :failed
          broker[:tries] = existing[:tries] + 1
          backoff = 1
          broker[:tries].times do |i|
            backoff = [backoff * 2, MAX_FAILED_BACKOFF].min
            break if backoff == MAX_FAILED_BACKOFF
          end
          broker[:backoff] = backoff
        end
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
        yield broker[:identity] if block_given?
        true
      end
    end

    # Remove a broker connection from the configuration
    # Invoke connection status callbacks only if connection is not already disabled
    # There is no check whether this is the last usable broker
    #
    # === Parameters
    # host{String):: IP host name or address for individual broker
    # port(Integer):: TCP port number for individual broker
    #
    # === Block
    # Optional block with following parameters to be called after removing the connection
    # unless broker is not configured:
    #   identity(String):: Broker identity
    #
    # === Return
    # identity(String|nil):: Identity of broker removed, or nil if unknown
    def remove(host, port, &blk)
      identity = self.class.identity(host, port)
      if broker = @brokers_hash[identity]
        RightLinkLog.info("Removing #{identity}, alias #{broker[:alias]} from broker list")
        if connection_closable(broker)
          # Not using close_one here because broker being removed immediately
          broker[:connection].close
          update_status(broker, :closed)
        end
        @brokers_hash.delete(identity)
        @brokers.reject! { |b| b[:identity] == identity }
        yield identity if block_given?
      else
        RightLinkLog.info("Ignored request to remove #{identity} because unknown")
        identity = nil
      end
      identity
    end

    # Declare a broker connection as unusable
    #
    # === Parameters
    # identities(Array):: Identity of brokers
    #
    # === Return
    # true:: Always return true
    #
    # === Raises
    # Exception:: If identified broker is unknown
    def declare_unusable(identities)
      identities.each do |id|
        broker = @brokers_hash[id]
        raise Exception, "Cannot mark unknown broker #{id} unusable" unless broker
        broker[:connection].close if connection_closable(broker)
        update_status(broker, :failed)
      end
    end
 
    # Provide callback to be activated when there is a change in connection status
    # Can be called more than once without affecting previous callbacks
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
    # Block to be called when connected count crosses a status boundary; it must accept the following parameters:
    #   status(Symbol):: Status of connection
    #
    # === Return
    # id(String):: Identifier associated with connection status request
    def connection_status(options = {}, &blk)
      id = AgentIdentity.generate
      @connection_status[id] = {:boundary => options[:boundary], :brokers => options[:brokers], :block => blk}
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

    # Provide callback to be activated when a broker returns a message that could not be delivered
    # A message published with :mandatory => true is returned if the exchange does not have any associated queues
    # A message published with :immediate => true is returned if all of the queues associated with the exchange do
    # not have any consumers
    #
    # === Block
    # Block with following parameters to be called when a message is returned:
    #   identity(String):: Broker identity
    #   reason(Symbol):: Reason for return
    #     :NOT_DELIVERED - a :mandatory => true failure
    #     :NO_CONSUMERS - an :immediate => true failure
    #   packet(Packet|String):: Returned message in unserialized packet format if serializer defined and could
    #     unserialize it, otherwise the serialized message
    #
    # === Return
    # true:: Always return true
    def return_message(&blk)
      each_usable do |b|
        b[:mq].return_message do |info, msg|
          begin
            reason = AMQP::RESPONSES[info.reply_code]
            packet = msg
            describe = msg.inspect
            if @serializer
              begin
                packet = @serializer.load(msg)
                describe = "#{packet.to_s([:target])}"
              rescue Exception => e
                RightLinkLog.warn("Failed to unserialize message from broker #{b[:alias]}: #{e}")
                packet = msg
                describe = msg.inspect
              end
            end
            RightLinkLog.info("RETURN [#{b[:alias]}] #{reason.to_s} #{info.exchange} #{describe}")
            blk.call(b[:identity], reason, packet)
          rescue Exception => e
            RightLinkLog.error("Failed return #{info.inspect} of message from broker #{b[:alias]}: #{e}")
          end
        end
      end
      true
    end

    # Provide callback to be activated when the HA_MQ rescues an exception during operation.
    #
    # === Block
    # Block with following parameters to be called when an exception is raised while receiving:
    #   msg(String):: the message content that caused an exception
    #   e(Exception):: the exception that was raised
    #   ha_mq(HA_MQ):: the HA_MQ object that raised the exception
    #
    # === Return
    # true:: always returns true
    def exception_on_receive(&blk)
      @exception_on_receive = blk
      true
    end

    # Get broker status
    #
    # === Return
    # (Array(Hash)):: Status of each configured broker:
    #   :identity(String):: Broker identity
    #   :alias(String):: Broker alias used in logs
    #   :status(Symbol):: Status of connection
    #   :tries(Integer):: Number of attempts to reconnect a failed connection
    def status
      @brokers.map { |b| b.reject { |k, _| ![:identity, :alias, :status, :tries].include?(k) } }
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

    # Close all broker connections
    #
    # === Block
    # Optional block with no parameters to be called after all connections are closed
    #
    # === Return
    # true:: Always return true
    def close(&blk)
      unless @closed
        @closed = true
        handler = CountedDeferrable.new(@brokers.size)
        handler.callback { blk.call if blk }
        @brokers.each do |b|
          begin
            close_one(b[:identity], propagate = false) { handler.completed_one }
          rescue Exception => e
            handler.completed_one
            RightLinkLog.error("Failed to close broker #{b[:alias]}: #{e.message}")
          end
        end
      end
      true
    end

    # Close an individual broker connection
    #
    # === Parameters
    # identity(String):: Broker identity
    # propagate(Boolean):: Whether to propagate connection status updates
    #
    # === Block
    # Optional block with no parameters to be called after connection closed
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # Exception:: If broker unknown
    def close_one(identity, propagate = true)
      broker = @brokers_hash[identity]
      raise Exception, "Cannot close unknown broker #{identity}" unless broker

      if connection_closable(broker)
        begin
          RightLinkLog.info("[stop] Closed connection to broker #{broker[:alias]}")
          update_status(broker, :closed) if propagate
          broker[:connection].close do
            broker[:status] = :closed
            yield if block_given?
          end
        rescue Exception => e
          RightLinkLog.error("Failed to close broker #{broker[:alias]}: #{e.message}")
          broker[:status] = :closed
          yield if block_given?
        end
      else
        broker[:status] = :closed
        yield if block_given?
      end
      true
    end

    protected

    # Helper for deferring block execution until specified number of actions have completed
    # or timeout occurs
    class CountedDeferrable

      include EM::Deferrable

      # Defer action until completion count reached or timeout occurs
      #
      # === Parameter
      # count(Integer):: Number of completions required for action
      # timeout(Integer|nil):: Number of seconds to wait for all completions and if
      #   reached, proceed with action; nil means no timing
      def initialize(count, timeout = nil)
        @timer = EM::Timer.new(timeout) { succeed } if timeout
        @count = count
      end

      # Completed one part of task
      #
      # === Return
      # true:: Always return true
      def completed_one
        if (@count -= 1) == 0
          @timer.cancel if @timer
          succeed
        end
        true
      end

    end

    # Extract host name from broker identity
    #
    # === Parameters
    # identity{String):: Broker identity
    #
    # === Returns
    # (String):: IP host name
    def host(identity)
      AgentIdentity.parse(identity).token.gsub('~', '-')
    end

    # Extract port number from broker identity
    #
    # === Parameters
    # identity{String):: Broker identity
    #
    # === Returns
    # (Integer):: TCP port number
    def port(identity)
      AgentIdentity.parse(identity).base_id
    end

    # Iterate over usable broker connections
    # A broker is considered usable if still connecting or confirmed connected
    #
    # === Parameters
    # identities(Array):: Identity of brokers to be considered, nil or empty array means all brokers
    #
    # === Block
    # Optional block with following parameters to be called for each usable broker:
    #   broker(Hash):: Broker attributes
    #
    # === Return
    # (Array):: Usable brokers
    def each_usable(identities = nil)
      choices = if identities && !identities.empty?
        choices = identities.inject([]) { |c, i| if b = @brokers_hash[i] then c << b else c end }
      else
        @brokers
      end
      choices.select do |b|
        if [:connected, :connecting].include?(b[:status])
          yield(b) if block_given?
          true
        end
      end
    end

    # Make broker connection and register for status updates
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
        :identity   => self.class.identity(address[:host], address[:port]),
        :alias      => "b#{address[:id]}",
        :status     => :connecting,
        :queues     => [],
        :tries      => 0,
        :backoff    => 0
      }
      begin
        RightLinkLog.info("[setup] Connecting to broker #{broker[:identity]}, alias #{broker[:alias]}")
        broker[:connection] = AMQP.connect(:user   => options[:user],
                                           :pass   => options[:pass],
                                           :vhost  => options[:vhost],
                                           :host   => address[:host],
                                           :port   => address[:port],
                                           :insist => options[:insist] || false,
                                           :retry  => options[:retry] || 15)
        broker[:mq] = MQ.new(broker[:connection])
        broker[:mq].__send__(:connection).connection_status { |status| update_status(broker, status) }
      rescue Exception => e
        broker[:status] = :failed
        RightLinkLog.error("Failed connecting to #{broker[:alias]}: #{e.message}")
        broker[:connection].close if broker[:connection]
      end
      broker
    end

    # Receive message by unserializing it, checking that it is an acceptable type, and logging accordingly
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
    # (Packet|nil):: Unserialized packet or nil if not of right type or if there is an exception
    def receive(broker, queue, msg, options = {})
      begin
        packet = @serializer.load(msg)
        if options.key?(packet.class)
          unless options[:no_log] && RightLinkLog.level != :debug
            re = "RE-" if packet.respond_to?(:tries) && !packet.tries.empty?
            log_filter = options[packet.class] unless RightLinkLog.level == :debug
            RightLinkLog.info("#{re}RECV #{broker[:alias]} #{packet.to_s(log_filter)} #{options[:log_data]}")
          end
          packet
        else
          category = options[:category] + " " if options[:category]
          RightLinkLog.warn("RECV #{broker[:alias]} - Invalid #{category}packet type: #{packet.class}")
          nil
        end
      rescue Exception => e
        RightLinkLog.error("RECV #{broker[:alias]} - Failed receiving from queue #{queue}: #{e.message}")
        @exception_on_receive.call(msg, e, self) if @exception_on_receive
        nil
      end
    end

    # Callback from AMQP with connection status
    # Makes client callback with :connected or :disconnected status if boundary crossed
    #
    # === Parameters
    # broker(Hash):: Broker reporting status
    # status(Symbol):: Status of connection (:connected, :ready, :disconnected, :failed, :closed)
    #
    # === Return
    # true:: Always return true
    def update_status(broker, status)
      before = connected
      # Wait until connection is ready (i.e. handshake with broker is completed) before
      # changing our status to connected
      return if status == :connected
      broker[:status] = status == :ready ? :connected : status
      after = connected
      if status == :failed
        RightLinkLog.error("Failed to connect to broker #{broker[:alias]}")
      end
      unless before == after
        RightLinkLog.info("[status] Broker #{broker[:alias]} is now #{status}, connected brokers: [#{aliases(after).join(", ")}]")
      end
      @connection_status.reject! do |k, v|
        reject = false
        if v[:brokers].nil? || v[:brokers].include?(broker[:identity])
          b, a, n = if v[:brokers].nil?
            [before, after, @brokers.size]
          else
            [before & v[:brokers], after & v[:brokers], v[:brokers].size]
          end
          update = if v[:boundary] == :all
            if b.size < n && a.size == n
              :connected
            elsif b.size == n && a.size < n
              :disconnected
            end
          else
            if b.size == 0 && a.size > 0
              :connected
            elsif b.size > 0 && a.size == 0
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
    #   :brokers(Array):: Identity of brokers selected for use, defaults to all if nil or empty
    #   :order(Symbol):: Broker selection order: :random or :priority,
    #     defaults to @select if :brokers is nil, otherwise defaults to :priority
    #
    # === Return
    # (Array):: Allowed brokers in the order to be used
    def use(options)
      choices = []
      select = options[:order]
      if options[:brokers] && !options[:brokers].empty?
        options[:brokers].each do |a|
          if choice = @brokers_hash[a]
            choices << choice
          else
            RightLinkLog.error("Invalid broker id #{a.inspect}, check server configuration")
          end
        end
      else
        choices = @brokers
        select ||= @select
      end
      if select == :random
        choices.sort_by { rand }
      else
        choices
      end
    end

  end # HA_MQ

end # RightScale
