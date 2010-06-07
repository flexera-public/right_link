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

# monkey patch to the amqp gem that adds :no_declare => true option for new 
# Exchange objects. This allows us to send messages to exchanges that are
# declared by the mappers and that we have no configuration privileges on.
# temporary until we get this into amqp proper
MQ::Exchange.class_eval do
  def initialize(mq, type, name, opts = {})
    @mq = mq
    @type, @name, @opts = type, name, opts
    @mq.exchanges[@name = name] ||= self
    @key = opts[:key]

    @mq.callback{
      @mq.send AMQP::Protocol::Exchange::Declare.new({ :exchange => name,
                                                       :type => type,
                                                       :nowait => true }.merge(opts))
    } unless name == "amq.#{type}" or name == ''  or opts[:no_declare]
  end
end

begin
  # Horrible evil hack to implement AMQP connection backoff until the AMQP gem contains our patches
  require 'amqp'

  AMQP::Client.module_eval do
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
        RightScale::RightLinkLog.send(@reconnect_log, ["Reconnecting to AMQP broker #{@settings[:host]}:#{@settings[:port]}"])
        @reconnect_log = :error if (@reconnect_try % 300) == 0
      end
      @reconnect_try += 1
      log 'reconnecting'
      EM.reconnect(@settings[:host], @settings[:port], self)
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

    STATUS = [:uninitialized, :connected, :disconnected, :closed]
    INACCESSIBLE = [:uninitialized, :closed]

    # Create connections to all configured AMQP brokers
    #
    # === Parameters
    # options(Hash):: Configuration options:
    #   :user(String):: User name
    #   :pass(String):: Password
    #   :vhost(String):: Virtual host path name
    #   :insist(Boolean):: Whether to suppress redirection of connection
    #   :retry(Integer|Proc):: Number of seconds before try to reconnect or proc returning same
    #   :host(String):: Comma-separated list of AMQP broker hosts; if only one, it is reapplied
    #     to successive ports; if none, defaults to 0.0.0.0
    #   :port(String):: Comma-separated list of AMQP broker ports corresponding to :host list;
    #      if only one, it is incremented and applied to successive hosts; if none, defaults to 5672
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: If :host and :port are not matched lists
    def initialize(options)
      hosts = if options[:host] then options[:host].split(',') else [ nil ] end
      ports = if options[:port] then options[:port].to_s.split(',') else [ ::AMQP::PORT ] end
      if hosts.size != ports.size && hosts.size != 1 && ports.size != 1
        raise RightScale::Exceptions::Argument, "Unmatched AMQP host/port lists -- " +
                                                "hosts: #{options[:host].inspect} ports: #{options[:port].inspect}"
      end
      i = -1
      @mqs = if hosts.size > 1
        hosts.map { |host| i += 1; connect(host, if ports[i] then ports[i].to_i else ports[0].to_i + i end, options) }
      else
        ports.map { |port| i += 1; connect(if hosts[i] then hosts[i] else hosts[0] end, port, options) }
      end
    end

    # Iterate over AMQP broker connections
    #
    # === Block
    # Required block to which each AMQP broker connection is passed
    def each
      @mqs.each { |mq| yield mq unless INACCESSIBLE.include?(mq[:status]) }
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
      @mqs.each { |mq| mq[:mq].prefetch(value) unless INACCESSIBLE.include?(mq[:status]) }
      true
    end

    # Subscribe an AMQP queue to an AMQP exchange
    #
    # === Parameters
    # queue(Hash):: AMQP queue being subscribed with keys :name and :options
    # exchange(Hash):: AMQP exchange to subscribe to with keys :type, :name, and :options
    # options(Hash):: AMQP subscribe options
    #
    # === Block
    # Required block called each time exchange matches message to queue
    #
    # === Return
    # true:: Always return true
    def subscribe(queue, exchange, options = {}, &blk)
      @mqs.each do |mq|
        unless INACCESSIBLE.include?(mq[:status])
          q = mq[:mq].queue(queue[:name], queue[:options])
          x = mq[:mq].__send__(exchange[:type], exchange[:name], exchange[:options])
          q.bind(x).subscribe(options, &blk)
        end
      end
      true
    end

    # Delete queue
    #
    # === Parameters
    # name(String):: Queue name
    #
    # === Return
    # true:: Always return true
    def delete(name)
      @mqs.each { |mq| mq[:mq].queue(name).delete rescue nil }
      true
    end

    # Publish message to AMQP exchange of first usable broker, or all usable brokers
    # if fanout requested
    #
    # === Parameters
    # exchange(Hash):: AMQP exchange to subscribe to with keys :type, :name, and :options
    # message(String):: Serialized message to publish
    # options(Hash):: Publish options -- standard AMQP ones plus
    #   :fanout(Boolean):: true means publish to all usable brokers
    #   :restrict(Array(String)):: Host:port addresses of restricted broker set to use
    #
    # === Return
    # ids(Array(AgentIdentity)):: Identity of all AMQP brokers where message was published
    #
    # === Raise
    # (RightScale::Exceptions::IO):: If cannot find a usable AMQP broker connection
    def publish(exchange, message, options = {})
      ids = []
      @mqs.each do |mq|
        if mq[:status] == :connected && (options[:restrict].nil? || options[:restrict].include?("#{mq[:address]}"))
          begin
            mq[:mq].__send__(exchange[:type], exchange[:name], exchange[:options]).publish(message, options)
            ids << mq[:identity]
            break unless options[:fanout]
          rescue Exception => e
            RightLinkLog.error("Failed to publish to exchange #{exchange.inspect} on AMQP broker #{mq[:identity]}: #{e.message}")
          end
        end
      end
      if ids.empty?
        count = (options[:restrict].size if options[:restrict]) || @mqs.size
        raise RightScale::Exceptions::IO, "None of #{count} AMQP broker connections are usable"
      end
      ids
    end

    # Store block to be called when there is a change in connection status
    #
    # === Block
    # Required block to be called when usable connection count crosses 0|1 threshold
    #
    # === Return
    # true:: Always return true
    def connection_status(&blk)
      @connection_status = blk
      true
    end

    # Close all AMQP broker connections
    #
    # === Block
    # optional block to be executed after all connections are closed
    def close
      @mqs.each do |mq|
        mq[:mq].instance_variable_get('@connection').close if mq[:status] != :uninitialized
        mq[:status] = :closed
      end
      yield if block_given?
    end

    protected

    # Make AMQP broker connection and register for status updates
    #
    # === Parameters
    # host(String):: AMQP broker host
    # port(Integer):: AMQP broker port
    # options(Hash):: Options required to create an AMQP connection other than :host and :port
    #
    # === Return
    # mq(Hash):: AMQP broker
    #   :mq(MQ):: AMQP connection
    #   :address(String):: Host:port address of broker
    #   :status(Symbol):: Status of connection
    def connect(host, port, options)
      port = port.to_i
      connection = AMQP.connect(
        :user => options[:user],
        :pass => options[:pass],
        :vhost => options[:vhost],
        :host => host,
        :port => port,
        :insist => options[:insist] || false,
        :retry => options[:retry] || 15 )
      address = "#{host}:#{port}"
      identity = AgentIdentity.new('rs', 'broker', port, host)
      begin
        mq = {:mq => MQ.new(connection), :identity => identity, :address => address, :status => :connected}
        mq[:mq].__send__(:connection).connection_status { |status| update_status(mq, status) }
        RightLinkLog.info("Connected to AMQP broker #{identity}")
        mq
      rescue Exception => e
        RightLinkLog.warn("Failed to connect to AMQP broker #{identity}")
        {:mq => nil, :address => address, :status => :uninitialized}
      end
    end

    # Count number of usable AMQP broker connections
    #
    # === Return
    # count(Integer):: Number of usable connections
    def connected
      count = 0
      @mqs.each { |mq| count += 1 if mq[:status] == :connected }
      count
    end

    # Callback from AMQP with connection status
    #
    # === Parameters
    # mq(Hash):: AMQP broker reporting status
    # status(Symbol):: Status of connection (:connected, :disconnected)
    #
    # === Return
    # true:: Always return true
    def update_status(mq, status)
      before = connected
      mq[:status] = status
      after = connected
      RightLinkLog.info("AMQP broker #{mq[:identity]} is now #{status}. There are now #{after} usable brokers.")
      if before == 0 && after > 0
        @connection_status.call(:connected) if @connection_status
      elsif before > 0 && after == 0
        @connection_status.call(:disconnected) if @connection_status
      end
    end

  end # HA_MQ

end # RightScale