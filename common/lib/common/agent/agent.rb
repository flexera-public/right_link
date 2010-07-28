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

  # Agent for receiving messages from the mapper and acting upon them
  # by dispatching to a registered actor to perform. See load_actors
  # for details on how the agent specific environment is loaded.
  class Agent

    include ConsoleHelper
    include DaemonizeHelper

    # (String) Identity of this agent
    attr_reader :identity

    # (Hash) Configuration options applied to the agent
    attr_reader :options

    # (Dispatcher) Dispatcher for messages received
    attr_reader :dispatcher

    # (ActorRegistry) Registry for this agents actors
    attr_reader :registry

    # (HA_MQ) High availability AMQP broker
    attr_reader :broker

    # (Array) Tag strings published to mapper by agent
    attr_reader :tags

    # (Hash) Callback procedures; key is callback symbol and value is callback procedure
    attr_reader :callbacks

    # (String) Name of AMQP input queue shared by this agent with others of same type
    attr_reader :shared_queue

    # (Proc) Callable object that returns agent load as a string
    attr_accessor :status_proc

    # Seconds to wait after last request received before terminating
    TERMINATION_WAIT_TIME = 30

    # Default option settings for the agent
    DEFAULT_OPTIONS = COMMON_DEFAULT_OPTIONS.merge({
      :user => 'agent',
      :shared_queue => false,
      :fresh_timeout => nil,
      :retry_interval => nil,
      :retry_timeout => nil,
      :prefetch => 1,
      :persist => 'none',
      :ping_time => 60,
      :default_services => []
    }) unless defined?(DEFAULT_OPTIONS)

    # Seconds to wait for broker connection
    BROKER_CONNECT_TIMEOUT = 60

    # Initializes a new agent and establishes an AMQP connection.
    # This must be used inside EM.run block or if EventMachine reactor
    # is already started, for instance, by a Thin server that your Merb/Rails
    # application runs on.
    #
    # === Options
    #
    # Agent options:
    #
    # :identity(String):: Identity of this agent
    # :shared_queue(String):: Name of AMPQ queue to be used for input in addition to identity queue.
    #   This is a queue that is shared by multiple agents and hence, unlike the identity queue,
    #   is only able to receive requests, not results.
    # :status_proc(Proc):: Callable object that returns agent load as a string. Defaults to load
    #   averages string extracted from `uptime`.
    # :format(Symbol):: Format to use for packets serialization -- :marshal, :json or :yaml or :secure.
    #   Defaults to Ruby's Marshall format. For interoperability with AMQP clients implemented in other
    #   languages, use JSON. Note that the nanite code uses JSON gem, and ActiveSupport's JSON encoder
    #   may cause clashes if ActiveSupport is loaded after JSON gem. Also, using the secure format
    #   requires prior initialization of the serializer (see RightScale::SecureSerializer.init).
    # :root(String):: Application root for this agent. Defaults to Dir.pwd.
    # :log_dir(String):: Log file path. Defaults to the current working directory.
    # :file_root(String):: Path to directory to files this agent provides. Defaults to app_root/files.
    # :ping_time(Numeric):: Time interval in seconds between two subsequent heartbeat messages this agent
    #   broadcasts. Default value is 15.
    # :console(Boolean):: true indicates to start interactive console
    # :daemonize(Boolean):: true indicates to daemonize
    # :pid_dir(String):: Path to the directory where the agent stores its pid file (only if daemonized).
    #   Defaults to the root or the current working directory.
    # :persist(String):: Instructions for the AMQP broker for saving messages to persistent storage
    #   so they aren't lost when the broker is restarted:
    #     none - do not persist any messages
    #     all - persist all push and request messages
    #     push - only persist one-way request messages
    #     request - only persist two-way request messages and their associated result
    #   Can be overridden on a per-message basis using the persistence option.
    # :fresh_timeout(Numeric):: Maximum age in seconds before a request times out and is rejected
    # :retry_interval(Numeric):: Number of seconds between request retries
    # :retry_timeout(Numeric):: Maximum number of seconds to retry request before give up
    # :prefetch(Integer):: Maximum number of messages the AMQP broker is to prefetch for this agent
    #   before it receives an ack. Value 1 ensures that only last unacknowledged gets redelivered
    #   if the agent crashes. Value 0 means unlimited prefetch.
    # :callbacks(Hash):: Callbacks to be executed on specific events. Key is event (currently
    #   only :exception is supported) and value is the Proc to be called back. For :exception
    #   the parameters are exception, message being processed, and reference to agent. It gets called
    #   whenever a packet generates an exception.
    # :services(Symbol):: List of services provided by this agent. Defaults to all methods exposed by actors.
    # :secure(Boolean):: true indicates to use Security features of rabbitmq to restrict nanites to themselves
    # :single_threaded(Boolean):: true indicates to run all operations in one thread; false indicates
    #   to do requested work on EM defer thread and all else, such as pings on main thread
    # :threadpool_size(Integer):: Number of threads in EM thread pool
    #
    # Connection options:
    #
    # :vhost(String):: AMQP broker vhost that should be used
    # :user(String):: AMQP broker user
    # :pass(String):: AMQP broker password
    # :host(String):: Comma-separated list of AMQP broker hosts; if only one, it is reapplied
    #   to successive ports; if none, defaults to localhost
    # :port(Integer):: Comma-separated list of AMQP broker ports corresponding to hosts; if only one,
    #   it is incremented and applied to successive hosts; if none, defaults to 5672
    #
    # On start config.yml is read, so it is common to specify options in the YAML file. However, when both
    # Ruby code options and YAML file specify options, Ruby code options take precedence.
    #
    # === Return
    # agent(Agent):: New agent
    def self.start(opts = {})
      agent = new(opts)
      agent.run
      agent
    end

    # Initialize the new agent
    #
    # === Parameters
    # opts(Hash):: Configuration options per #start above
    #
    # === Return
    # true:: Always return true
    def initialize(opts)
      set_configuration(opts)
      @tags = []
      @tags << opts[:tag] if opts[:tag]
      @tags.flatten!
      @options.freeze
      @terminating = false
      true
    end

    # Put the agent in service
    #
    # === Return
    # true:: Always return true
    def run
      RightLinkLog.init(@identity, @options[:log_path])
      RightLinkLog.level = @options[:log_level] if @options[:log_level]
      begin
        # Capture process id in file after optional daemonize
        pid_file = PidFile.new(@identity, @options)
        pid_file.check
        daemonize(@identity, @options) if @options[:daemonize]
        pid_file.write
        at_exit { pid_file.remove }

        # Initiate AMQP broker connection, wait for connection before proceeding
        # otherwise messages published on failed connection will be lost
        @broker = HA_MQ.new(Serializer.new(@options[:format]), @options)
        @broker.connection_status(:one_off => BROKER_CONNECT_TIMEOUT) do |status|
          if status == :connected
            EM.next_tick do
              begin
                @registry = ActorRegistry.new
                @dispatcher = Dispatcher.new(self)
                @mapper_proxy = MapperProxy.new(self)
                load_actors
                setup_traps
                setup_queues
                advertise_services
                setup_heartbeat
                at_exit { un_register } unless $TESTING
                start_console if @options[:console] && !@options[:daemonize]
              rescue Exception => e
                RightLinkLog.error("Agent failed startup: #{e.message}\n" + e.backtrace.join("\n")) unless e.message == "exit"
                EM.stop
              end
            end
          else
            RightLinkLog.error("Failed to connect to any AMQP brokers")
            EM.stop
          end
        end
      rescue SystemExit => e
        raise e
      rescue Exception => e
        RightLinkLog.error("Agent failed startup: #{e.message}\n" + e.backtrace.join("\n")) unless e.message == "exit"
        raise e
      end
      true
    end

    # Register an actor for this agent
    #
    # === Parameters
    # actor(Actor):: Actor to be registered
    # prefix(String):: Prefix to be used in place of actor's default_prefix
    #
    # === Return
    # (Actor):: Actor registered
    def register(actor, prefix = nil)
      @registry.register(actor, prefix)
    end

    # Advertise the services provided by this agent
    #
    # === Parameters
    # connected(Array):: Identity of connected brokers, defaults to all connected brokers
    #
    # === Return
    # true:: Always return true
    def advertise_services(connected = nil)
      connected = @broker.connected unless connected
      exchange = {:type => :fanout, :name => 'registration', :options => {:no_declare => @options[:secure], :durable => true}}
      packet = Register.new(@identity, @registry.services, status_proc.call, self.tags, connected, @shared_queue)
      publish(exchange, packet) unless @terminating
      true
    end

    # Update set of tags published by agent and notify mapper
    # Add tags in 'new_tags' and remove tags in 'old_tags'
    #
    # === Parameters
    # new_tags(Array):: Tags to be added
    # obsolete_tags(Array):: Tags to be removed
    #
    # === Return
    # true:: Always return true
    def update_tags(new_tags, obsolete_tags)
      @tags += (new_tags || [])
      @tags -= (obsolete_tags || [])
      @tags.uniq!
      exchange = {:type => :fanout, :name => "request", :options => {:no_declare => @options[:secure], :durable => true}}
      packet = Push.new("/mapper/update_tags", {:new_tags => new_tags, :obsolete_tags => obsolete_tags},
                        :from => @identity, :persistent => true)
      publish(exchange, packet, :persistent => true) unless @terminating
      true
    end

    # Connect to an additional broker or reconnect it if connection has failed
    # Subscribe to identity queue on this broker
    # Update config file if this is a new broker
    # Assumes already has credentials on this broker and identity queue exists
    #
    # === Parameters
    # host(String):: Host name of broker
    # port(Integer):: Port number of broker
    # id(Integer):: Small unique id associated with this broker for use in forming alias
    # priority(Integer|nil):: Priority position of this broker in list for use
    #   by this agent with nil meaning add to end of list
    # force(Boolean):: Reconnect even if already connected
    #
    # === Return
    # res(String|nil):: Error message if failed, otherwise nil
    def connect(host, port, id, priority = nil, force = false)
      even_if = " even if already connected" if force
      RightLinkLog.info("Received request to connect to broker at host #{host.inspect} port #{port.inspect} " +
                        "id #{id.inspect} priority #{priority.inspect}#{even_if}")
      RightLinkLog.info("Current broker configuration: #{@broker.status.inspect}")
      res = nil
      begin
        @broker.connect(host, port, id, priority, force) do |b|
          @broker.connection_status(:one_off => BROKER_CONNECT_TIMEOUT, :brokers => [b[:identity]]) do |status|
            begin
              if status == :connected
                setup_identity_queue(b)
                setup_shared_queue(b) if @shared_queue
                advertise_services
                unless update_configuration(:host => @broker.hosts, :port => @broker.ports)
                  RightLinkLog.warn("Successfully connected to #{b[:identity]} but failed to update config file")
                end
              else
                RightLinkLog.error("Failed to connect to #{b[:identity]}, status #{status.inspect}")
              end
            rescue Exception => e
              RightLinkLog.error("Failed to connect to #{b[:identity]}, status #{status.inspect}: #{e.message}")
            end
          end
        end
      rescue Exception => e
        res = "Failed to connect to broker #{@broker.identity(host, port)}: #{e.message}"
      end
      RightLinkLog.error(res) if res
      res
    end

    # Disconnect from a broker and optionally remove it from the configuration
    # Refuse to do so if it is the last connected broker
    #
    # === Parameters
    # host(String):: Host name of broker
    # port(Integer):: Port number of broker
    # remove(Boolean):: Whether to remove broker from configuration rather than just closing it,
    #   defaults to false
    #
    # === Return
    # res(String|nil):: Error message if failed, otherwise nil
    def disconnect(host, port, remove = false)
      and_remove = " and remove" if remove
      RightLinkLog.info("Received request to disconnect#{and_remove} broker at host #{host.inspect} " +
                        "port #{port.inspect}")
      RightLinkLog.info("Current broker configuration: #{@broker.status.inspect}")
      identity = @broker.identity(host, port)
      connected = @broker.connected
      res = nil
      if connected.include?(identity) && connected.size == 1
        res = "Cannot disconnect from #{identity} because it is the last connected broker for this agent"
      elsif @broker.get(identity)
        begin
          if connected.include?(identity)
            # Need to advertise that no longer connected so that no more messages are routed through it
            connected.delete(identity)
            advertise_services(connected)
          end
          if remove
            @broker.remove(host, port) do |identity|
              unless update_configuration(:host => @broker.hosts, :port => @broker.ports)
                res = "Successfully disconnected from #{identity} but failed to update config file"
              end
            end
          else
            @broker.close_one(identity)
          end
        rescue Exception => e
          res = "Failed to disconnect from broker #{identity}: #{e.message}"
        end
      else
        res = "Cannot disconnect from #{identity} because not configured for this agent"
      end
      RightLinkLog.error(res) if res
      res
    end

    # Declare one or more broker connections unusable because connection has failed
    # If these are the last usable connections, attempt to recreate them now; otherwise mark
    # them is as unusable and defer reconnect attempt to next mapper ping, since this agent
    # may still not be registered with those brokers
    #
    # === Parameters
    # ids(Array):: Identity of brokers
    #
    # === Return
    # res(String|nil):: Error message if failed, otherwise nil
    def connect_failed(ids)
      res = nil
      begin
        RightLinkLog.info("Connection to brokers #{ids.inspect} has failed")
        connected = @broker.connected
        if (connected - ids).empty?
          # No more usable connections so try recreating now
          ids.each do |id|
            connect(@broker.host(id), @broker.port(id), @broker.id_(id), @broker.priority(id), force = true)
          end
        else
          # Defer reconnect initiation to the mapper via ping
          @broker.not_usable(ids)
          advertise_services
        end
      rescue Exception => e
        res = "Failed to mark brokers #{ids.inspect} as unusable: #{e.message}"
        RightLinkLog.error(res)
      end
      res
    end

    # Gracefully terminate execution by allowing unfinished tasks to complete
    # Immediately terminate if called a second time
    #
    # === Block
    # Optional block to be executed after termination is complete
    #
    # === Return
    # true:: Always return true
    def terminate(&blk)
      if @terminating
        RightLinkLog.info("[stop] Terminating immediately")
        @termination_timer.cancel if @termination_timer
        if blk then blk.call else EM.stop end
      else
        @terminating = true
        RightScale::RightLinkLog.info("[stop] Agent #{@options[:identity]} terminating")
        un_register
        @broker.unsubscribe(@shared_queue) do
          requests = @mapper_proxy.pending_requests.size
          request_age = @mapper_proxy.request_age
          dispatch_age = @dispatcher.dispatch_age
          wait_time = [TERMINATION_WAIT_TIME - (request_age || TERMINATION_WAIT_TIME),
                       TERMINATION_WAIT_TIME - (dispatch_age || TERMINATION_WAIT_TIME), 0].max
          if wait_time > 0
            reason = ""
            reason = "completion of #{requests} unfinished requests started as recently as #{request_age} seconds ago" if request_age
            reason += " and " if request_age && dispatch_age
            reason += "requests dispatched as recently as #{dispatch_age} seconds ago" if dispatch_age
            RightLinkLog.info("[stop] Termination waiting #{wait_time} seconds for #{reason}")
          end
          @termination_timer = EM::Timer.new(wait_time) do
            request_age = @mapper_proxy.request_age
            if wait_time > 0 && request_age
              requests = @mapper_proxy.pending_requests.size
              RightLinkLog.info("[stop] Continuing with termination with #{requests} unfinished requests " +
                                "started as recently as #{request_age} seconds ago")
            elsif wait_time > 0
              RightLinkLog.info("[stop] Continuing with termination")
            end
            @broker.close(&blk)
            EM.stop unless blk
          end
        end
      end
      true
    end

    protected

    # Set the agent's configuration using the supplied options
    #
    # === Parameters
    # opts(Hash):: Configuration options
    #
    # === Return
    # true:: Always return true
    def set_configuration(opts)
      @options = DEFAULT_OPTIONS.clone
      root = opts[:root] || @options[:root]
      custom_config = if root
        file = File.normalize_path(File.join(root, 'config.yml'))
        File.exists?(file) ? (YAML.load(IO.read(file)) || {}) : {}
      else
        {}
      end
      opts.delete(:identity) unless opts[:identity]
      @options.update(custom_config.merge(opts))
      @options[:file_root] ||= File.join(@options[:root], 'files')
      @options[:log_path] = false
      if @options[:daemonize] || @options[:log_dir]
        @options[:log_path] = (@options[:log_dir] || @options[:root] || Dir.pwd)

        # create the path if is does not exist.  Added for windows, but is a good practice.
        FileUtils.mkdir_p(@options[:log_dir])
      end

      if @options[:identity]
        @identity = "nanite-#{@options[:identity]}"
      else
        token = AgentIdentity.generate
        @identity = "nanite-#{token}"
        File.open(File.normalize_path(File.join(@options[:root], 'config.yml')), 'w') do |fd|
          fd.write(YAML.dump(custom_config.merge(:identity => token)))
        end
      end

      @callbacks = @options[:callbacks]
      @status_proc = @options[:status_proc] || lambda { parse_uptime(`uptime 2> /dev/null`) rescue 'no status' }
      @shared_queue = @options[:shared_queue]

      return @identity
    end

    # Update agent's persisted configuration
    # Note that @options are frozen and therefore not updated
    #
    # === Parameters
    # opts(Hash):: Options being updated
    #
    # === Return
    # (Boolean):: true if successful, otherwise false
    def update_configuration(opts)
      res = false
      root = opts[:root] || @options[:root]
      config = if root
        file = File.normalize_path(File.join(root, 'config.yml'))
        File.exists?(file) ? (YAML.load(IO.read(file)) || nil) : nil
      end
      if config
        File.open(File.normalize_path(File.join(root, 'config.yml')), 'w') do |fd|
          fd.write(YAML.dump(config.merge(opts)))
        end
        res = true
      end
      res
    end

    # Load the ruby code for the actors
    #
    # === Return
    # false:: If there is no :root option
    # true:: Otherwise
    def load_actors
      return false unless @options[:root]
      actors_dir = @options[:actors_dir] || "#{@options[:root]}/actors"
      RightLinkLog.warn("Actors dir #{actors_dir} does not exist or is not reachable") unless File.directory?(actors_dir)
      actors = @options[:actors]
      RightLinkLog.info("[setup] Agent #{@identity} with actors #{actors.inspect}")
      Dir["#{actors_dir}/*.rb"].each do |actor|
        next if actors && !actors.include?(File.basename(actor, ".rb"))
        RightLinkLog.info("[setup] loading #{actor}")
        require actor
      end
      init_path = @options[:initrb] || File.join(@options[:root], 'init.rb')
      if File.exists?(init_path)
        instance_eval(File.read(init_path), init_path)
      else
        RightLinkLog.warn("init.rb #{init_path} does not exist or is not reachable") unless File.exists?(init_path)
      end
      true
    end

    # Setup the queues for this agent
    #
    # === Return
    # true:: Always return true
    def setup_queues
      @broker.prefetch(@options[:prefetch]) if @options[:prefetch]
      @broker.each_usable do |b|
        setup_identity_queue(b)
        setup_shared_queue(b) if @shared_queue
      end
      true
    end

    # Setup identity queue for this agent
    # For non-instance agents also attach queue to advertise exchange
    #
    # === Parameters
    # broker(Hash):: Individual broker to which agent is connected
    #
    # === Return
    # true:: Always return true
    def setup_identity_queue(broker)
      handler = lambda do |info, msg|
        begin
          # Ack now before processing message to avoid risk of duplication after a crash
          info.ack
          if msg == "nil"
            # This happens as part of connecting to a broker
            RightLinkLog.debug("RECV #{broker[:alias]} nil message ignored")
          else
            filter = [:from, :tags, :tries, :persistent]
            packet = @broker.receive(broker, @identity, msg, Advertise => nil, Request => filter, Push => filter, Result => [])
            case packet
            when Advertise then advertise_services unless @terminating
            when Request then @dispatcher.dispatch(packet) unless @terminating
            when Push then @dispatcher.dispatch(packet) unless @terminating
            when Result then @mapper_proxy.handle_result(packet)
            end
          end
        rescue Exception => e
          RightLinkLog.error("RECV - Identity queue processing error: #{e.message}")
          @callbacks[:exception].call(e, msg, self) rescue nil if @callbacks && @callbacks[:exception]
        end
      end

      RightLinkLog.info("[setup] Subscribing queue #{@identity} on #{broker[:alias]}")

      queue = broker[:mq].queue(@identity, :durable => true, :no_declare => @options[:secure])
      broker[:queues] << queue

      if AgentIdentity.parse(@identity).instance_agent?
        queue.subscribe(:ack => true, &handler)
      else
        # Explicitly create direct exchange and bind queue to it
        # since binding this queue to multiple exchanges
        binding = queue.bind(broker[:mq].direct(@identity, :durable => true, :auto_delete => true))

        # Non-instance agents must also bind to the advertise exchange so that
        # a mapper that comes up after this agent can learn of its existence. The identity
        # queue binds to both the identity and advertise exchanges, therefore the advertise
        # exchange must be durable to match the identity exchange.
        queue.bind(broker[:mq].fanout("advertise", :durable => true))

        binding.subscribe(:ack => true, &handler)
      end
    end

    # Setup shared queue for this agent
    # This queue is only allowed to receive requests
    # Not for use by instance agents
    #
    # === Parameters
    # broker(Hash):: Individual broker to which agent is connected
    #
    # === Return
    # true:: Always return true
    #
    # === Raises
    # Exception:: If this is an instance agent
    def setup_shared_queue(broker)
      raise Exception, "Instance agents cannot use shared queues" if AgentIdentity.parse(@identity).instance_agent?
      RightLinkLog.info("[setup] Subscribing queue #{@shared_queue} on #{broker[:alias]}")
      queue = broker[:mq].queue(@shared_queue, :durable => true)
      broker[:queues] << queue
      exchange = broker[:mq].direct(@shared_queue,  :durable => true)
      queue.bind(exchange).subscribe(:ack => true) do |info, msg|
        begin
          # Ack now before processing message to avoid risk of duplication after a crash
          info.ack
          filter = [:from, :tags, :tries, :persistent]
          request = @broker.receive(broker, @identity, msg, Request => filter, Push => filter, :category => "request")
          @dispatcher.dispatch(request)
        rescue Exception => e
          RightLinkLog.error("RECV - Shared queue processing error: #{e.message}")
          @callbacks[:exception].call(e, request, self) rescue nil if @callbacks && @callbacks[:exception]
        end
      end
      true
    end

    # Setup the periodic sending of a Ping packet to the heartbeat queue
    #
    # === Return
    # true:: Always return true
    def setup_heartbeat
      EM.add_periodic_timer(@options[:ping_time]) do
        exchange = {:type => :fanout, :name => 'heartbeat', :options => {:no_declare => @options[:secure]}}
        packet = Ping.new(@identity, status_proc.call, @broker.connected, @broker.failed(backoff = true))
        publish(exchange, packet, :no_log => true) unless @terminating
      end
      true
    end

    # Setup signal traps
    #
    # === Return
    # true:: Always return true
    def setup_traps
      ['INT', 'TERM'].each do |sig|
        old = trap(sig) do
          terminate do
            EM.stop
            old.call if old.is_a? Proc
          end
        end
      end
      true
    end

    # Store unique tags
    #
    # === Parameters
    # tags(Array):: Tags to be added
    #
    # === Return
    # @tags(Array):: Current tags
    def tag(*tags)
      tags.each {|t| @tags << t}
      @tags.uniq!
    end

    # Publish packet to registration exchange
    #
    # === Parameters
    # exchange(Hash):: Exchange to which to publish packet
    # packet(Packet):: Packet to be published
    # options(Hash):: Publish options
    #
    # === Return
    # true:: Always return true
    def publish(exchange, packet, options = {})
      begin
        @broker.publish(exchange, packet, options)
      rescue Exception => e
        RightLinkLog.error("Failed to publish #{packet.class} to #{exchange[:name]} exchange: #{e.message}") unless @terminating
      end
      true
    end

    # Unregister this agent if not already unregistered
    #
    # === Return
    # true:: Always return true
    def un_register
      unless @unregistered
        @unregistered = true
        exchange = {:type => :fanout, :name => 'registration', :options => {:no_declare => @options[:secure], :durable => true}}
        publish(exchange, UnRegister.new(@identity))
      end
      true
    end

    # Parse the uptime string returned by the OS
    # Expected to contain 'load averages' followed by three floating point numbers
    #
    # === Parameters
    # up(String):: Uptime string
    #
    # === Return
    # (Float):: Uptime value if parsable
    # nil:: If not parsable
    def parse_uptime(up)
      if up =~ /load averages?: (.*)/
        a,b,c = $1.split(/\s+|,\s+/)
        (a.to_f + b.to_f + c.to_f) / 3
      end
    end

  end # Agent

end # RightScale
