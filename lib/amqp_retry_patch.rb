require 'rubygems'

begin
  # Horrible evil hack to implement AMQP connection backoff until the AMQP gem contains our patches
  require 'amqp'

  AMQP::Client.module_eval do
    def reconnect force = false
      if @reconnecting and not force
        # wait 1 second after first reconnect attempt, in between each subsequent attempt
        EM.add_timer(1){ reconnect(true) }
        return
      end

      unless @reconnecting
        @deferred_status = nil
        initialize(@settings)

        mqs = @channels
        @channels = {}
        mqs.each{ |_,mq| mq.reset } if mqs

        @reconnecting = true

        again = @settings[:retry]
        again = again.call if again.is_a?(Proc)

        if again == false
          #do not retry connection
          raise StandardError, "Could not reconnect to server #{@settings[:host]}:#{@settings[:port]}"
        elsif again.is_a?(Numeric)
          #retry connection after N seconds
          EM.add_timer(again){ reconnect(true) }
          return
        elsif (again != true && again != nil)
          raise StandardError, "Could not interpret reconnection retry action #{again}"
        end
      end

      log 'reconnecting'
      EM.reconnect @settings[:host], @settings[:port], self
    end
  end
rescue LoadError
  #LoadError indicates that the AMQP gem is not installed; we can ignore this
end

begin
  # Horrible evil hack to patch Nanite to account for our changes to the AMQP gem
  require 'nanite'

  Nanite::AMQPHelper.module_eval do
    def start_amqp(options)
      connection = AMQP.connect(:user => options[:user], :pass => options[:pass], :vhost => options[:vhost],
      :host => options[:host], :port => (options[:port] || ::AMQP::PORT).to_i, :insist => options[:insist] || false,
      :retry => options[:retry] || 15 )
      MQ.new(connection)
    end
  end
rescue LoadError
  #LoadError indicates that the Nanite gem is not installed; we can ignore this
end