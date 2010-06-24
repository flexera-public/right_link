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

    # (Serializer) Serializer used for marshaling messages
    attr_reader :serializer

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

    # Default option settings for the agent
    DEFAULT_OPTIONS = COMMON_DEFAULT_OPTIONS.merge({
      :user => 'agent',
      :shared_queue => false,
      :fresh_timeout => nil,
      :retry_interval => nil,
      :retry_timeout => nil,
      :prefetch => 1,
      :ping_time => 15,
      :default_services => []
    }) unless defined?(DEFAULT_OPTIONS)

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
    # :persistent(Boolean):: true instructs the AMQP broker to save messages to persistent storage so
    #   that they aren't lost when the broker is restarted. Default is false. Can be overridden on a
    #   per-message basis using the request and push methods of MapperProxy.
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
    # :infrastructure(Boolean):: true indicates this agent is part of the RightScale infrastructure
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
        @serializer = Serializer.new(@options[:format])
        @status_proc ||= lambda { parse_uptime(`uptime 2> /dev/null`) rescue 'no status' }
        pid_file = PidFile.new(@identity, @options)
        pid_file.check
        if @options[:daemonize]
          daemonize(@identity, @options)
        end
        pid_file.write
        at_exit { pid_file.remove }
        select = if @options[:infrastructure] then :random else :ordered end
        @broker = HA_MQ.new(@serializer, @options.merge(:select => select))
        @registry = ActorRegistry.new
        @dispatcher = Dispatcher.new(@broker, @registry, @identity, @options)
        @mapper_proxy = MapperProxy.new(@identity, @broker, @options)
        load_actors
        setup_traps
        setup_queues
        advertise_services
        setup_heartbeat
        at_exit { un_register } unless $TESTING
        start_console if @options[:console] && !@options[:daemonize]
      rescue SystemExit => e
        raise e
      rescue Exception => e
        RightLinkLog.error("Agent failed: #{e.message}\n" + e.backtrace.join("\n")) unless e.message == "exit"
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

    # Update set of tags published by agent and notify mapper
    # Add tags in 'new_tags' and remove tags in 'old_tags'
    #
    # === Parameters
    # new_tags(Array):: Tags to be added
    # old_tags(Array):: Tags to be removed
    #
    # === Return
    # true:: Always return true
    def update_tags(new_tags, old_tags)
      @tags += (new_tags || [])
      @tags -= (old_tags || [])
      @tags.uniq!
      publish('registration', TagUpdate.new(@identity, new_tags, old_tags))
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
      @status_proc = @options[:status_proc]
      @shared_queue = @options[:shared_queue]

      return @identity
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
      RightLinkLog.info("Agent #{@identity} actors #{actors.inspect}")
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
      setup_identity_queue
      setup_shared_queue if @shared_queue
      true
    end

    # Setup identity queue for this agent
    # For infrastructure agents also attach queue to advertise exchange
    #
    # === Return
    # true:: Always return true
    def setup_identity_queue
      @broker.each_usable do |b|
        handler = lambda do |info, msg|
          begin
            # Ack now before processing message to avoid risk of duplication after a crash
            info.ack
            filter = [:from, :tags, :tries]
            packet = @broker.receive(b, @identity, msg, Advertise => nil, Request => filter, Push => filter, Result => [])
            case packet
            when Advertise then advertise_services
            when Request, Push then @dispatcher.dispatch(packet)
            when Result then @mapper_proxy.handle_result(packet)
            end
          rescue Exception => e
            RightLinkLog.error("RECV - Identity queue processing error: #{e.message}")
            @callbacks[:exception].call(e, msg, self) rescue nil if @callbacks && @callbacks[:exception]
          end
        end

        queue = b[:mq].queue(@identity, :durable => true)
        if @options[:infrastructure]
          # Explicitly create direct exchange and bind queue to it
          # since binding this queue to multiple exchanges
          binding = queue.bind(b[:mq].direct(@identity, :durable => true, :auto_delete => true))

          # A RightScale infrastructure agent must also bind to the advertise exchange so that
          # a mapper that comes up after this agent can learn of its existence. The identity
          # queue binds to both the identity and advertise exchanges, therefore the advertise
          # exchange must be durable to match the identity exchange.
          queue.bind(b[:mq].fanout("advertise", :durable => true)) if @options[:infrastructure]

          binding.subscribe(:ack => true, &handler)
        else
          queue.subscribe(:ack => true, &handler)  
        end
      end
    end

    # Setup shared queue for this agent
    # This queue is only allowed to receive requests
    #
    # === Return
    # true:: Always return true
    def setup_shared_queue
      queue = {:name => @shared_queue, :options => {:durable => true}}
      exchange = {:type => :direct, :name => @shared_queue, :options => {:durable => true}}
      filter = [:from, :tags, :tries]
      @broker.subscribe(queue, exchange, :ack => true, Request => filter, Push => filter, :category => "request") do |request|
        begin
          @dispatcher.dispatch(request) if request
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
        publish('heartbeat', Ping.new(@identity, status_proc.call, @broker.connected), :no_log => true)
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
          @terminating = true
          un_register
          @broker.close do
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

    # Publish packet to exchange
    #
    # === Parameters
    # name(String):: Exchange name
    # packet(Packet):: Packet to be published
    # options(Hash):: Publish options
    #
    # === Return
    # true:: Always return true
    def publish(name, packet, options = {})
      exchange = {:type => :fanout, :name => name, :options => {:no_declare => @options[:secure]}}
      begin
        @broker.publish(exchange, packet, options)
      rescue Exception => e
        RightLinkLog.error("Failed to publish #{packet.class} to #{name} exchange: #{e.message}") unless @terminating
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
        publish('registration', UnRegister.new(@identity))
      end
      true
    end

    # Advertise the services provided by this agent
    #
    # === Return
    # true:: Always return true
    def advertise_services
      reg = Register.new(@identity, @registry.services, status_proc.call, self.tags, @broker.connected, @shared_queue)
      publish('registration', reg)
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
