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

  module AMQPHelper

    # Open AMQP broker connection
    #
    # === Parameters
    # options(Hash):: AMQP broker configuration options:
    #   :user(String):: User name
    #   :pass(String):: Password
    #   :vhost(String):: Virtual host path name
    #   :insist(Boolean):: Whether to suppress redirection of connection
    #   :retry(Integer|Proc):: Number of seconds before try to reconnect or proc returning same
    #   :host(String):: Host name
    #   :port(String|Integer):: Port number
    #
    # === Return
    # (MQ):: AMQP broker connection
    def start_amqp(options)
      connection = AMQP.connect(
        :user => options[:user],
        :pass => options[:pass],
        :vhost => options[:vhost],
        :host => options[:host],
        :port => (options[:port] || ::AMQP::PORT).to_i,
        :insist => options[:insist] || false,
        :retry => options[:retry] || 15 )
      MQ.new(connection)
    end

    # Open connections to multiple AMQP brokers for high availability operation
    #
    # === Parameters
    # options(Hash):: AMQP broker configuration options:
    #   :user(String):: User name
    #   :pass(String):: Password
    #   :vhost(String):: Virtual host path name
    #   :insist(Boolean):: Whether to suppress redirection of connection
    #   :retry(Integer|Proc):: Number of seconds before try to reconnect or proc returning same
    #   :host(String):: Comma-separated host names, reused if only one specified
    #   :port(String):: Comma-separated port number, defaults to AMQP::PORT with incrementing as needed
    #   :prefix(String):: Comma-separated broker identifiers that are used as queue/exchange name prefixes
    #
    # === Return
    # (Array(Hash)):: AMQP brokers
    #   :prefix(String):: Broker identifier that is used as queue/exchange name prefix
    #   :mq(MQ):: AMQP connection to broker
    def start_ha_amqp(options)
      amqp_opts = {
        :user => options[:user],
        :pass => options[:pass],
        :vhost => options[:vhost],
        :insist => options[:insist],
        :retry => options[:retry] }
      hosts = if options[:host] then options[:host].split(',') else [ nil ] end
      ports = if options[:port] then options[:port].split(',') else [ ::AMQP::PORT ] end
      prefixes = if options[:prefix] then options[:prefix].split(',') else [ nil ] end
      i = 0
      prefixes.map do |p|
        amqp_opts[:host] = if hosts[i] then hosts[i] else hosts[0] end
        amqp_opts[:port] = if ports[i] then ports[i] else ports[0].to_i + i end
        i += 1
        { :prefix => p, :mq => start_amqp(amqp_opts) }
      end
    end

    # Determine whether AMQP broker connection is available for service
    def usable(mq)
      mq.__send__(:connection).connected?
    end

  end # AMQPHelper

end # RightScale