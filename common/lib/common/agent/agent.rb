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
  # by dispatching them to a registered actor to perform. See load_actors
  # for details on how the agent specific environment is loaded.
  class Agent
    include AMQPHelper
    include ConsoleHelper
    include DaemonizeHelper

    attr_reader :identity, :options, :serializer, :dispatcher, :registry, :amq, :tags, :callbacks, :shared_queue
    attr_accessor :status_proc

    DEFAULT_OPTIONS = COMMON_DEFAULT_OPTIONS.merge({
      :user => 'nanite',
      :shared_queue => false,
      :ping_time => 15,
      :default_services => []
    }) unless defined?(DEFAULT_OPTIONS)

    # Initializes a new agent and establishes an AMQP connection.
    # This must be used inside EM.run block or if EventMachine reactor
    # is already started, for instance, by a Thin server that your Merb/Rails
    # application runs on.
    #
    # === Parameters
    # opts(Hash):: Options for configuring, connecting, and running agent
    #
    # Agent options:
    #
    # identity    : identity of this agent, may be any string
    #
    # shared_queue : name of AMPQ queue to be used for input in addition to identity queue,
    #               this is a queue that is shared by multiple agents and hence, unlike the
    #               identity queue, is only able to receive requests, not results
    #
    # status_proc : a callable object that returns agent load as a string,
    #               defaults to load averages string extracted from `uptime`
    #
    # format      : format to use for packets serialization. One of the three:
    #               :marshall, :json, or :yaml. Defaults to
    #               Ruby's Marshall format. For interoperability with
    #               AMQP clients implemented in other languages, use JSON.
    #
    #               Note that agents use JSON gem,
    #               and ActiveSupport's JSON encoder may cause clashes
    #               if ActiveSupport is loaded after JSON gem.
    #
    # root        : application root for this agent, defaults to Dir.pwd
    #
    # log_dir     : path to directory where agent stores it's log file
    #               if not given, app_root is used.
    #
    # file_root   : path to directory to files this agent provides
    #               defaults to app_root/files
    #
    # ping_time   : time interval in seconds between two subsequent heartbeat messages
    #               this agent broadcasts. Default value is 15.
    #
    # console     : true indicates to start interactive console
    #
    # daemonize   : true indicates to daemonize
    #
    # pid_dir     : path to the directory where the agent stores its pid file (only if daemonized)
    #               defaults to the root or the current working directory.
    #
    # services    : list of services provided by this agent, by default
    #               all methods exposed by actors are listed
    #
    # single_threaded: Run all operations in one thread
    #
    # threadpool_size: Number of threads to run operations in
    #
    #
    # Connection options:
    #
    # vhost       : AMQP broker vhost that should be used
    #
    # user        : AMQP broker user
    #
    # pass        : AMQP broker password
    #
    # host        : host AMQP broker (or node of interest) runs on,
    #               defaults to 0.0.0.0
    #
    # port        : port AMQP broker (or node of interest) runs on,
    #               this defaults to 5672, port used by some widely
    #               used AMQP brokers (RabbitMQ and ZeroMQ)
    #
    # callback    : Hash of proc objects defining well known callbacks
    #               Currently only the :exception callback is supported
    #               This block gets called whenever a packet generates an exception
    #
    # On start config.yml is read, so it is common to specify
    # options in the YAML file. However, when both Ruby code options
    # and YAML file specify option, Ruby code options take precedence.
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
    # opts(Hash):: Configuration options
    #
    # === Return
    # true:: Always return true
    def initialize(opts)
      set_configuration(opts)
      @tags = []
      @tags << opts[:tag] if opts[:tag]
      @tags.flatten!
      @options.freeze
      true
    end
    
    # Put the agent in service
    #
    # === Return
    # true:: Always return true
    def run
      RightLinkLog.init(@identity, @options[:log_path])
      RightLinkLog.level = @options[:log_level] if @options[:log_level]
      @serializer = Serializer.new(@options[:format])
      @status_proc ||= lambda { parse_uptime(`uptime 2> /dev/null`) rescue 'no status' }
      pid_file = PidFile.new(@identity, @options)
      pid_file.check
      if @options[:daemonize]
        daemonize(@identity, @options)
        pid_file.write
        at_exit { pid_file.remove }
      end
      @amq = start_amqp(@options)
      @registry = ActorRegistry.new
      @dispatcher = Dispatcher.new(@amq, @registry, @serializer, @identity, @options)
      setup_mapper_proxy
      load_actors
      setup_traps
      setup_queues
      advertise_services
      setup_heartbeat
      at_exit { un_register } unless $TESTING
      start_console if @options[:console] && !@options[:daemonize]
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
      tag_update = TagUpdate.new(@identity, new_tags, old_tags)
      @amq.fanout('registration', :no_declare => @options[:secure]).publish(@serializer.dump(tag_update))
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
        file = File.expand_path(File.join(root, 'config.yml'))
        File.exists?(file) ? (YAML.load(IO.read(file)) || {}) : {}
      else
        {}
      end
      opts.delete(:identity) unless opts[:identity]
      @options.update(custom_config.merge(opts))
      @options[:file_root] ||= File.join(@options[:root], 'files')
      @options[:log_path] = false
      if @options[:daemonize]
        @options[:log_path] = (@options[:log_dir] || @options[:root] || Dir.pwd)
      end

      if @options[:identity]
        @identity = "nanite-#{@options[:identity]}"
      else
        token = AgentIdentity.generate
        @identity = "nanite-#{token}"
        File.open(File.expand_path(File.join(@options[:root], 'config.yml')), 'w') do |fd|
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
      Dir["#{actors_dir}/*.rb"].each do |actor|
        next if actors && !actors.include?(File.basename(actor, ".rb"))
        RightLinkLog.info("[setup] loading #{actor}")
        require actor
      end
      init_path = @options[:initrb] || File.join(@options[:root], 'init.rb')
      if File.exist?(init_path)
        instance_eval(File.read(init_path), init_path) 
      else
        RightLinkLog.warn("init.rb #{init_path} does not exist or is not reachable") unless File.exists?(init_path)
      end
      true
    end

    # Receive and process a packet of any type
    #
    # === Parameters
    # packet(Packet>:: Packet to receive
    #
    # === Return
    # true:: Always return true
    def receive_any(packet)
      RightLinkLog.debug("RECV #{packet.to_s}")
      case packet
      when Advertise
        RightLinkLog.info("RECV #{packet.to_s}") unless RightLinkLog.level == :debug
        advertise_services
      when Request, Push
        RightLinkLog.info("RECV #{packet.to_s([:from, :tags])}") unless RightLinkLog.level == :debug
        @dispatcher.dispatch(packet)
      when Result
        RightLinkLog.info("RECV #{packet.to_s([])}") unless RightLinkLog.level == :debug
        @mapper_proxy.handle_result(packet)
      else
        RightLinkLog.error("Agent #{@identity} received invalid packet: #{packet.to_s}")
      end
      true
    end

    # Receive and process a Request or Push packet; any other type is invalid
    #
    # === Parameters
    # packet(Packet>:: Packet to receive
    #
    # === Return
    # true:: Always return true
    def receive_request(packet)
      RightLinkLog.debug("RECV #{packet.to_s}")
      case packet
      when Request, Push
        RightLinkLog.info("RECV #{packet.to_s([:from, :tags])}") unless RightLinkLog.level == :debug
        @dispatcher.dispatch(packet)
      else
        RightLinkLog.error("Agent #{@identity} received invalid request packet: #{packet.to_s}")
      end
      true
    end

    # Setup the queues for this agent
    #
    # === Return
    # true:: Always return true
    def setup_queues
      [@identity, @shared_queue].each do |queue|
        if queue
          # Restrict non-identity queues to only receiving requests
          receive_method = if queue == @identity then :receive_any else :receive_request end

          @amq.queue(queue, :durable => true).subscribe(:ack => true) do |info, msg|
            begin
              info.ack
              __send__(receive_method, @serializer.load(msg))
            rescue Exception => e
              RightLinkLog.error("RECV #{e.message}")
              @callbacks[:exception].call(e, msg, self) rescue nil if @callbacks && @callbacks[:exception]
            end
          end
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
        @amq.fanout('heartbeat', :no_declare => @options[:secure]).publish(@serializer.dump(Ping.new(@identity, status_proc.call)))
      end
      true
    end
    
    # Setup the mapper proxy for use in handling results
    #
    # === Return
    # @mapper_proxy(MapperProxy):: Mapper proxy created
    def setup_mapper_proxy
      @mapper_proxy = MapperProxy.new(@identity, @options)
    end
    
    # Setup signal traps
    #
    # === Return
    # true:: Always return true
    def setup_traps
      ['INT', 'TERM'].each do |sig|
        old = trap(sig) do
          un_register
          @amq.instance_variable_get('@connection').close do
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

    # Unregister this agent if not already unregistered
    #
    # === Return
    # true:: Always return true
    def un_register
      unless @unregistered
        @unregistered = true
        RightLinkLog.info("SEND [un_register]")
        @amq.fanout('registration', :no_declare => @options[:secure]).publish(@serializer.dump(UnRegister.new(@identity)))
      end
      true
    end

    # Advertise the services provided by this agent
    #
    # === Return
    # true:: Always return true
    def advertise_services
      reg = Register.new(@identity, @registry.services, status_proc.call, self.tags, @shared_queue)
      RightLinkLog.info("SEND #{reg.to_s}")
      @amq.fanout('registration', :no_declare => @options[:secure]).publish(@serializer.dump(reg))
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
