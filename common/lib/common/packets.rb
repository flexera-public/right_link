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


# Hack to replace the Nanite namespace from downrev agents with the RightScale namespace
module JSON
  class << self
    def parse(source, opts = {})
      if source =~ /(.*)json_class":"Nanite::(.*)/
        JSON.parser.new( Regexp.last_match(1) + 'json_class":"RightScale::' + Regexp.last_match(2), opts).parse
      else
        JSON.parser.new(source, opts).parse
      end
    end
  end
end


module RightScale

  # Base class for all packets flowing through the mappers
  # Knows how to dump itself to JSON
  class Packet

    # Current version of protocol
    VERSION = RightLinkConfig.protocol_version

    # Default version for packet senders unaware of this versioning
    DEFAULT_VERSION = 0

    attr_accessor :size

    def initialize
      raise NotImplementedError.new("#{self.class.name} is an abstract class.")
    end

    # Marshal packet into JSON format
    #
    # === Parameters
    # a(Array):: Arguments
    #
    # === Return
    # js(String):: Marshalled packet
    def to_json(*a)
      # Hack to override RightScale namespace with Nanite for downward compatibility
      class_name = self.class.name
      if class_name =~ /^RightScale::(.*)/
        class_name = "Nanite::" + Regexp.last_match(1)
      end

      js = {
        'json_class'   => class_name,
        'data'         => instance_variables.inject({}) {|m,ivar| m[ivar.to_s.sub(/@/,'')] = instance_variable_get(ivar); m }
      }.to_json(*a)
      js = js.chop + ",\"size\":#{js.size}}"
      js
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      log_msg = "[#{ self.class.to_s.split('::').last.
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        downcase }]"
      log_msg += " (#{@size.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")} bytes)" if @size && !@size.to_s.empty?
      log_msg
    end

    # Generate log friendly name
    #
    # === Parameters
    # id(String):: Agent id
    #
    # === Return
    # (String):: Log friendly name
    def id_to_s(id)
      case id
        when /^mapper-/ then 'mapper'
        when /^nanite-(.*)/ then Regexp.last_match(1)
        else id
      end
    end

    # Get target to be used for encrypting the packet
    #
    # === Return
    # (String):: Target
    def target_for_encryption
      nil
    end

    # Generate token used to trace execution of operation across multiple packets
    #
    # === Return
    # tr(String):: Trace token, may be empty
    def trace
      audit_id = self.respond_to?(:payload) && payload.is_a?(Hash) && (payload['audit_id'] || payload[:audit_id])
      tok = self.respond_to?(:token) && token
      tr = ''
      if audit_id || tok
        tr = '<'        
        if audit_id 
          tr += audit_id.to_s
          tr += ':' if tok
        end
        tr += tok if tok
        tr += '>'
      end
      tr  
    end

  end # Packet


  # Packet for a work request for an actor node that has an expected result
  class Request < Packet

    attr_accessor :from, :scope, :payload, :type, :token, :reply_to, :selector, :target, :persistent, :created_at,
                  :tags, :tries, :returns

    DEFAULT_OPTIONS = {:selector => :random}

    # Create packet
    #
    # === Parameters
    # type(String):: Service name
    # payload(Any):: Arbitrary data that is transferred to actor
    # opts(Hash):: Optional settings:
    #   :from(String):: Sender identity
    #   :scope(Hash):: Define behavior that should be used to resolve tag based routing
    #   :token(String):: Generated request id that a mapper uses to identify replies
    #   :reply_to(String):: Identity of the node that actor replies to, usually a mapper itself
    #   :selector(Symbol):: Selector used to route the request: :all or :random,
    #   :target(String):: Target recipient
    #   :persistent(Boolean):: Indicates if this request should be saved to persistent storage
    #     by the AMQP broker
    #   :created_at(Fixnum):: Time in seconds in Unix-epoch when this request was created for
    #      use in timing out the request; value 0 means never timeout; defaults to current time
    #   :tags(Array(Symbol)):: List of tags to be used for selecting target for this request
    #   :tries(Array):: List of tokens for previous attempts to send this request
    #   :returns(Array):: Identity of brokers which returned request as undeliverable
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(type, payload, opts = {}, size = nil)
      opts = DEFAULT_OPTIONS.merge(opts)
      @type       = type
      @payload    = payload
      @from       = opts[:from]
      @scope      = opts[:scope]
      @token      = opts[:token]
      @reply_to   = opts[:reply_to]
      @selector   = opts[:selector]
      @selector   = :random if @selector.to_s == "least_loaded"
      @target     = opts[:target]
      @persistent = opts[:persistent]
      @created_at = opts[:created_at] || Time.now.to_f
      @tags       = opts[:tags] || []
      @tries      = opts[:tries] || []
      @returns    = opts[:returns] || []
      @broker
      @size       = size
    end

    # Test whether the request potentially is expecting results from multiple agents
    # The initial result for any such request contains a list of the responders
    #
    # === Return
    # (Boolean):: true if is multicast, otherwise false
    def multicast?
      (!@scope.nil?) || (@selector.to_s == 'all') || (!@tags.nil? && !@tags.empty?)
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Request):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['type'], i['payload'], { :from       => i['from'],       :scope    => i['scope'],
                                     :token      => i['token'],      :reply_to => i['reply_to'],
                                     :selector   => i['selector'],   :target   => i['target'],   
                                     :persistent => i['persistent'], :tags     => i['tags'],
                                     :created_at => i['created_at'], :tries    => i['tries'],
                                     :returns    => i['returns'] },
          o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      payload = PayloadFormatter.log(@type, @payload)
      log_msg = "#{super} #{trace} #{@type}"
      log_msg += " #{payload}" if payload
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += " with scope #{@scope}" if @scope && (filter.nil? || filter.include?(:scope))
      log_msg += " target #{id_to_s(@target)}" if @target && (filter.nil? || filter.include?(:target))
      log_msg += ", reply_to #{id_to_s(@reply_to)}" if @reply_to && (filter.nil? || filter.include?(:reply_to))
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
      log_msg += ", tries #{tries_to_s}" if @tries && !@tries.empty? && (filter.nil? || filter.include?(:tries))
      log_msg += ", returns #{@returns.inspect}" if @returns && !@returns.empty? && (filter.nil? || filter.include?(:returns))
      log_msg += ", payload #{@payload.inspect}" if filter.nil? || filter.include?(:payload)
      log_msg
    end

    # Convert tries list to string representation
    #
    # === Return
    # log_msg(String):: Tries list
    def tries_to_s
      log_msg = ""
      @tries.each { |r| log_msg += "<#{r}>, " }
      log_msg = log_msg[0..-3] if log_msg.size > 1
    end

    # Get target to be used for encrypting the packet
    #
    # === Return
    # (String):: Target
    def target_for_encryption
      @target
    end

  end # Request


  # Packet for a work request for an actor node that has no result, i.e., one-way request
  class Push < Packet

    attr_accessor :from, :scope, :payload, :type, :token, :selector, :target, :persistent, :created_at, :tags,
                  :tries, :returns

    DEFAULT_OPTIONS = {:selector => :random}

    # Create packet
    #
    # === Parameters
    # type(String):: Service name
    # payload(Any):: Arbitrary data that is transferred to actor
    # opts(Hash):: Optional settings:
    #   :from(String):: Sender identity
    #   :scope(Hash):: Define behavior that should be used to resolve tag based routing
    #   :token(String):: Generated request id that a mapper uses to identify replies
    #   :selector(Symbol):: Selector used to route the request: :all or :random,
    #   :target(String):: Target recipient
    #   :persistent(Boolean):: Indicates if this request should be saved to persistent storage
    #     by the AMQP broker
    #   :created_at(Fixnum):: Time in seconds in Unix-epoch when this request was created for
    #     use in timing out the request; value 0 means never timeout; defaults to current time
    #   :tags(Array(Symbol)):: List of tags to be used for selecting target for this request
    #   :tries(Array):: List of tokens for previous attempts to send this request (only here
    #     for consistency with Request)
    #   :returns(Array):: Identity of brokers which returned request as undeliverable
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(type, payload, opts = {}, size = nil)
      opts = DEFAULT_OPTIONS.merge(opts)
      @type       = type
      @payload    = payload
      @from       = opts[:from]
      @scope      = opts[:scope]
      @token      = opts[:token]
      @selector   = opts[:selector]
      @selector   = :random if @selector.to_s == "least_loaded"
      @target     = opts[:target]
      @persistent = opts[:persistent]
      @created_at = opts[:created_at] || Time.now.to_f
      @tags       = opts[:tags] || []
      @tries      = opts[:tries] || []
      @returns    = opts[:returns] || []
      @size       = size
    end

    # Test whether the request potentially is being sent to multiple agents
    #
    # === Return
    # (Boolean):: true if is multicast, otherwise false
    def multicast?
      (!@scope.nil?) || (@selector.to_s == 'all') || (!@tags.nil? && !@tags.empty?)
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Push):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['type'], i['payload'], { :from   => i['from'],   :scope      => i['scope'],
                                     :token  => i['token'],  :selector   => i['selector'],
                                     :target => i['target'], :persistent => i['persistent'],
                                     :tags   => i['tags'],   :created_at => i['created_at'],
                                     :tries  => i['tries'],  :returns    => i['returns'] },
          o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      payload = PayloadFormatter.log(@type, @payload)
      log_msg = "#{super} #{trace} #{@type}"
      log_msg += " #{payload}" if payload
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += " with scope #{@scope}" if @scope && (filter.nil? || filter.include?(:scope))
      log_msg += ", target #{id_to_s(@target)}" if @target && (filter.nil? || filter.include?(:target))
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
      log_msg += ", tries #{tries_to_s}" if @tries && !@tries.empty? && (filter.nil? || filter.include?(:tries))
      log_msg += ", returns #{@returns.inspect}" if @returns && !@returns.empty? && (filter.nil? || filter.include?(:returns))
      log_msg += ", payload #{@payload.inspect}" if filter.nil? || filter.include?(:payload)
      log_msg
    end

    # Get target to be used for encrypting the packet
    #
    # === Return
    # (String):: Target
    def target_for_encryption
      @target
    end

  end # Push


  # Packet for a work result notification sent from actor node
  class Result < Packet

    attr_accessor :token, :results, :to, :from, :request_from, :tries, :persistent, :returns, :created_at

    # Create packet
    #
    # === Parameters
    # token(String):: Generated request id that a mapper uses to identify replies
    # to(String):: Identity of the node to which result should be delivered
    # results(Any):: Arbitrary data that is transferred from actor, a result of actor's work
    # from(String):: Sender identity
    # request_from(String):: Identity of the node that sent the original request
    # tries(Array):: List of tokens for previous attempts to send associated request
    # persistent(Boolean):: Indicates if this result should be saved to persistent storage
    #   by the AMQP broker
    # returns(Array):: Identity of brokers which returned request as undeliverable
    # created_at(Fixnum):: Time in seconds in Unix-epoch when this result was created
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(token, to, results, from, request_from = nil, tries = nil, persistent = nil,
                   returns = nil, created_at = nil,  size = nil)
      @token        = token
      @to           = to
      @results      = results
      @from         = from
      @request_from = request_from
      @tries        = tries || []
      @returns      = returns || []
      @persistent   = persistent
      @created_at   = created_at || Time.now.to_f
      @size         = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Result):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['token'], i['to'], i['results'], i['from'], i['request_from'], i['tries'], i['persistent'], i['returns'], i['created_at'],
          o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      log_msg = "#{super} #{trace}"
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += " to #{id_to_s(@to)}" if filter.nil? || filter.include?(:to)
      log_msg += " request_from #{id_to_s(@request_from)}" if @request_from && (filter.nil? || filter.include?(:request_from))
      log_msg += " persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
      log_msg += " tries #{tries_to_s}" if @tries && !@tries.empty? && (filter.nil? || filter.include?(:tries))
      log_msg += " returns #{@returns.inspect}" if @returns && !@returns.empty? && (filter.nil? || filter.include?(:returns))
      if filter.nil? || !filter.include?(:results)
        if !@results.nil?
          if @results.is_a?(RightScale::OperationResult)
            res = @results # Will be true when logging a 'SEND'
          elsif @results.is_a?(Hash) && @results.size == 1 # Will be true when logging a 'RECV'
            res = @results.values.first
          end
          log_msg += " #{res.to_s}" if res
        end
      else
        log_msg += " results #{@results.inspect}"
      end
      log_msg
    end

    # Convert tries list to string representation
    #
    # === Return
    # log_msg(String):: Tries list
    def tries_to_s
      log_msg = ""
      @tries.each { |r| log_msg += "<#{r}>, " }
      log_msg = log_msg[0..-3] if log_msg.size > 1
    end

    # Get target to be used for encrypting the packet
    #
    # === Return
    # (String):: Target
    def target_for_encryption
      @to
    end

  end # Result


  # Packet for reporting a stale request packet
  class Stale < Packet

    attr_accessor :identity, :token, :from, :created_at, :received_at, :timeout

    # Create packet
    #
    # === Parameters
    # identity(String):: Identity of agent reporting the stale request
    # token(String):: Generated id for stale request
    # from(String):: Identity of originator of stale request
    # created_at(Fixnum):: Time in seconds in Unix-epoch when originator created message
    #   plus any mapper adjustment for clock skew
    # received_at(Fixnum):: Time in seconds in Unix-epoch when agent detected stale message
    # timeout(Integer):: Maximum message age before considered stale
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, token, from, created_at, received_at, timeout, size = nil)
      @identity    = identity
      @token       = token
      @from        = from
      @created_at  = created_at
      @received_at = received_at
      @timeout     = timeout
      @size        = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Result):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['token'], i['from'], i['created_at'], i['received_at'], i['timeout'], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      log_msg = "#{super} #{trace} #{id_to_s(@identity)}"
      log_msg += " from #{id_to_s(@from)} created_at #{@created_at.to_i}"
      log_msg += " received_at #{@received_at.to_i} timeout #{@timeout}"
      log_msg
    end

  end # Stale


  # Deprecated for instance agents
  #
  # Packet for availability notification from an agent to the mappers
  class Register < Packet

    attr_accessor :identity, :services, :tags, :brokers, :shared_queue, :created_at, :version

    # Create packet
    #
    # === Parameters
    # identity(String):: Sender identity
    # services(Array):: List of services provided by the node
    # tags(Array(Symbol)):: List of tags associated with this service
    # brokers(Array|nil):: Identity of agent's brokers with nil meaning not supported
    # shared_queue(String):: Name of a queue shared between this agent and another
    # created_at(Fixnum):: Time in seconds in Unix-epoch when this registration was created
    # version(Integer):: Protocol version of agent registering
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, services, tags, brokers, shared_queue = nil, created_at = nil, version = VERSION, size = nil)
      @tags         = tags
      @brokers      = brokers
      @identity     = identity
      @services     = services
      @shared_queue = shared_queue
      @created_at   = created_at || Time.now.to_f
      @version      = version
      @size         = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Register):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['services'], i['tags'], i['brokers'], i['shared_queue'], i['created_at'],
          i['version'] || DEFAULT_VERSION, o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      log_msg = "#{super} #{id_to_s(@identity)}"
      log_msg += ", version #{@version}"
      log_msg += ", shared_queue #{@shared_queue}" if @shared_queue
      log_msg += ", services #{@services.inspect}" if @services && !@services.empty?
      log_msg += ", brokers #{@brokers.inspect}" if @brokers && !@brokers.empty?
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty?
      log_msg
    end

  end # Register


  # Deprecated for instance agents
  #
  # Packet for unregistering an agent from the mappers
  class UnRegister < Packet

    attr_accessor :identity

    # Create packet
    #
    # === Parameters
    # identity(String):: Sender identity
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, size = nil)
      @identity = identity
      @size     = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (UnRegister):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['identity'], o['size'])
    end
  
    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # (String):: Log representation
    def to_s(filter = nil)
      "#{super} #{id_to_s(@identity)}"
    end

  end # UnRegister


  # Deprecated
  #
  # Heartbeat packet
  class Ping < Packet

    attr_accessor :identity, :status, :connected, :failed, :created_at

    # Create packet
    #
    # === Parameters
    # identity(String):: Sender identity
    # status(Any):: Load of the node by default, but may be any criteria
    #   agent may use to report its availability, load, etc
    # connected(Array|nil):: Identity of agent's connected brokers, nil means not supported
    # failed(Array|nil):: Identity of agent's failed brokers, i.e., ones it never was able
    #   to connect to, nil means not supported
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, status, connected = nil, failed = nil, size = nil)
      @status     = status
      @identity   = identity
      @connected  = connected
      @failed     = failed
      @size       = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Ping):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['status'], i['connected'], i['failed'], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # (String):: Log representation
    def to_s(filter = nil)
      "#{super} #{id_to_s(@identity)} status #{@status}, connected #{@connected.inspect}, failed #{@failed.inspect}"
    end

  end # Ping


  # Packet for requesting an agent to advertise its services to the mappers
  # when it initially comes online or when its heartbeat times out
  class Advertise < Packet

    # Create packet
    #
    # === Parameters
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(size = nil)
      @size = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (Advertise):: New packet
    def self.json_create(o)
      i = o['data']
      new(o['size'])
    end

  end # Advertise


  # Deprecated: instead use /mapper/update_tags
  #
  # Packet for an agent to update the mappers with its tags
  class TagUpdate < Packet

    attr_accessor :identity, :new_tags, :obsolete_tags

    # Create packet
    #
    # === Parameters
    # identity(String):: Sender identity
    # new_tags(Array):: List of new tags
    # obsolete_tags(Array):: List of tags to be deleted
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, new_tags, obsolete_tags, size = nil)
      @identity      = identity
      @new_tags      = new_tags
      @obsolete_tags = obsolete_tags
      @size          = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (TagUpdate):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['new_tags'], i['obsolete_tags'], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # (String):: Log representation
    def to_s(filter = nil)
      log_msg = "#{super} #{id_to_s(@identity)}"
      log_msg += ", new tags #{@new_tags.inspect}" if @new_tags && !@new_tags.empty?
      log_msg += ", obsolete tags #{@obsolete_tags.inspect}" if @obsolete_tags && !@obsolete_tags.empty?
      log_msg
    end

  end # TagUpdate


  # Deprecated: instead use Request of type /mapper/tag_query with :tags and :agent_ids in payload
  #
  # Packet for requesting retrieval of agents with specified tags
  class TagQuery < Packet

    attr_accessor :from, :token, :agent_ids, :tags, :persistent

    # Create packet
    #
    # === Parameters
    # from(String):: Sender identity
    # opts(Hash):: Options, at least one must be set:
    #   :tags(Array):: Tags defining a query that returned agents tags must match
    #   :agent_ids(Array):: ids of agents that should be returned
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(from, opts, size = nil)
      @from       = from
      @token      = opts[:token]
      @agent_ids  = opts[:agent_ids]
      @tags       = opts[:tags]
      @persistent = opts[:persistent]
      @size       = size
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: JSON data
    #
    # === Return
    # (TagQuery):: New packet
    def self.json_create(o)
      i = o['data']
      new(i['from'], { :token => i['token'], :agent_ids => i['agent_ids'],
                       :tags => i['tags'],   :persistent => i['persistent'] },
          o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil)
      log_msg = "#{super} #{trace}"
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += " agent_ids #{@agent_ids.inspect}"
      log_msg += " tags #{@tags.inspect}"
      log_msg
    end

  end # TagQuery

end # RightScale

