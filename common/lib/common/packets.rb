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
  # Knows how to dump itself to MessagePack or JSON
  class Packet

    # Current version of protocol
    VERSION = RightLinkConfig.protocol_version

    # Default version for packet senders unaware of this versioning
    DEFAULT_VERSION = 0

    attr_accessor :size

    def initialize
      raise NotImplementedError.new("#{self.class.name} is an abstract class.")
    end

    # Create packet from unmarshalled MessagePack data
    #
    # === Parameters
    # o(Hash):: MessagePack data
    #
    # === Return
    # (Packet):: New packet
    def self.msgpack_create(o)
      create(o)
    end

    # Create packet from unmarshalled JSON data
    #
    # === Parameters
    # o(Hash):: MessagePack data
    #
    # === Return
    # (Packet):: New packet
    def self.json_create(o)
      create(o)
    end

    # Marshal packet into MessagePack format
    #
    # === Parameters
    # a(Array):: Arguments
    #
    # === Return
    # msg(String):: Marshalled packet
    def to_msgpack(*a)
      msg = {
        'msgpack_class' => self.class.name,
        'data'          => instance_variables.inject({}) { |m, ivar| m[ivar.to_s.sub(/@/,'')] = instance_variable_get(ivar); m },
        'size'          => nil
      }.to_msgpack(*a)
      msg = msg.sub(/size\300/, "size#{msg.size.to_msgpack}")
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
        'json_class' => class_name,
        'data'       => instance_variables.inject({}) { |m, ivar| m[ivar.to_s.sub(/@/,'')] = instance_variable_get(ivar); m }
      }.to_json(*a)
      js = js.chop + ",\"size\":#{js.size}}"
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      v = __send__(version) if version
      v = (v && v != DEFAULT_VERSION) ? " v#{v}" : ""
      log_msg = "[#{ self.class.to_s.split('::').last.
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        downcase }#{v}]"
      log_msg += " (#{@size.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")} bytes)" if @size && !@size.to_s.empty?
      log_msg
    end

    # Generate log friendly serialized identity
    # Result marked with leading '*' if not same as original identity
    #
    # === Parameters
    # id(String):: Serialized identity
    #
    # === Return
    # (String):: Log friendly serialized identity
    def id_to_s(id)
      modified_id = AgentIdentity.compatible_serialized(id)
      if id == modified_id then modified_id else "*#{modified_id}" end
    end

    # Convert serialized AgentIdentity to compatible format
    #
    # === Parameters
    # id(String):: Serialized identity
    #
    # === Return
    # (String):: Compatible serialized identity
    def self.compatible(id)
      AgentIdentity.compatible_serialized(id)
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

    # Retrieve protocol version of original creator of packet
    #
    # === Return
    # (Integer) Received protocol version
    def recv_version
      @version[0]
    end

    # Retrieve protocol version of packet for use when sending packet
    #
    # === Return
    # (Integer) Send protocol version
    def send_version
      @version[1]
    end

    # Set protocol version of packet for use when sending packet
    def send_version=(value)
      @version[1] = value
    end

  end # Packet


  # Packet for a work request for an actor node that has an expected result
  class Request < Packet

    attr_accessor :from, :scope, :payload, :type, :token, :reply_to, :selector, :target, :persistent, :created_at,
                  :tags, :tries

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
    #   :selector(Symbol):: Selector used to route the request: :all or :random
    #   :target(String):: Target recipient
    #   :persistent(Boolean):: Indicates if this request should be saved to persistent storage
    #     by the AMQP broker
    #   :created_at(Fixnum):: Time in seconds in Unix-epoch when this request was created for
    #      use in timing out the request; value 0 means never timeout; defaults to current time
    #   :tags(Array(Symbol)):: List of tags to be used for selecting target for this request
    #   :tries(Array):: List of tokens for previous attempts to send this request
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(type, payload, opts = {}, version = [VERSION, VERSION], size = nil)
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
      @version    = version
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

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Request):: New packet
    def self.create(o)
      i = o['data']
      new(i['type'], i['payload'], { :from       => self.compatible(i['from']), :scope    => i['scope'],
                                     :token      => i['token'],                 :reply_to => self.compatible(i['reply_to']),
                                     :selector   => i['selector'],              :target   => self.compatible(i['target']),
                                     :persistent => i['persistent'],            :tags     => i['tags'],
                                     :created_at => i['created_at'],            :tries    => i['tries'] },
          i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      payload = PayloadFormatter.log(@type, @payload)
      log_msg = "#{super(filter, version)} #{trace} #{@type}"
      log_msg += " #{payload}" if payload
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += ", target #{id_to_s(@target)}" if @target && (filter.nil? || filter.include?(:target))
      log_msg += ", scope #{@scope}" if @scope && (filter.nil? || filter.include?(:scope))
      log_msg += ", multicast" if (filter.nil? || filter.include?(:multicast)) && multicast?
      log_msg += ", reply_to #{id_to_s(@reply_to)}" if @reply_to && (filter.nil? || filter.include?(:reply_to))
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
      log_msg += ", tries #{tries_to_s}" if @tries && !@tries.empty? && (filter.nil? || filter.include?(:tries))
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

    attr_accessor :from, :scope, :payload, :type, :token, :selector, :target, :persistent, :created_at, :tags

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
    #   :selector(Symbol):: Selector used to route the request: :all or :random
    #   :target(String):: Target recipient
    #   :persistent(Boolean):: Indicates if this request should be saved to persistent storage
    #     by the AMQP broker
    #   :created_at(Fixnum):: Time in seconds in Unix-epoch when this request was created for
    #     use in timing out the request; value 0 means never timeout; defaults to current time
    #   :tags(Array(Symbol)):: List of tags to be used for selecting target for this request
    #   :tries(Array):: List of tokens for previous attempts to send this request (only here
    #     for consistency with Request)
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(type, payload, opts = {}, version = [VERSION, VERSION], size = nil)
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
      @version    = version
      @size       = size
    end

    # Test whether the request potentially is being sent to multiple agents
    #
    # === Return
    # (Boolean):: true if is multicast, otherwise false
    def multicast?
      (!@scope.nil?) || (@selector.to_s == 'all') || (!@tags.nil? && !@tags.empty?)
    end

    # Keep interface consistent with Request packets
    # A push never gets retried
    #
    # === Return
    # []:: Always return empty array
    def tries; []; end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Push):: New packet
    def self.create(o)
      i = o['data']
      new(i['type'], i['payload'], { :from   => self.compatible(i['from']),   :scope      => i['scope'],
                                     :token  => i['token'],                   :selector   => i['selector'],
                                     :target => self.compatible(i['target']), :persistent => i['persistent'],
                                     :tags   => i['tags'],                    :created_at => i['created_at'] },
          i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      payload = PayloadFormatter.log(@type, @payload)
      log_msg = "#{super(filter, version)} #{trace} #{@type}"
      log_msg += " #{payload}" if payload
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += ", target #{id_to_s(@target)}" if @target && (filter.nil? || filter.include?(:target))
      log_msg += ", scope #{@scope}" if @scope && (filter.nil? || filter.include?(:scope))
      log_msg += ", multicast" if (filter.nil? || filter.include?(:multicast)) && multicast?
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
      log_msg += ", tries #{tries_to_s}" if @tries && !@tries.empty? && (filter.nil? || filter.include?(:tries))
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

    attr_accessor :token, :results, :to, :from, :request_from, :tries, :persistent, :created_at

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
    # created_at(Fixnum):: Time in seconds in Unix-epoch when this result was created
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(token, to, results, from, request_from = nil, tries = nil, persistent = nil,
                   created_at = nil, version = [VERSION, VERSION], size = nil)
      @token        = token
      @to           = to
      @results      = results
      @from         = from
      @request_from = request_from
      @tries        = tries || []
      @persistent   = persistent
      @created_at   = created_at || Time.now.to_f
      @version      = version
      @size         = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Result):: New packet
    def self.create(o)
      i = o['data']
      new(i['token'], self.compatible(i['to']), i['results'], self.compatible(i['from']),
          self.compatible(i['request_from']), i['tries'], i['persistent'], i['created_at'],
          i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      log_msg = "#{super(filter, version)} #{trace}"
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += " to #{id_to_s(@to)}" if filter.nil? || filter.include?(:to)
      log_msg += ", request_from #{id_to_s(@request_from)}" if @request_from && (filter.nil? || filter.include?(:request_from))
      log_msg += ", persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
      log_msg += ", tries #{tries_to_s}" if @tries && !@tries.empty? && (filter.nil? || filter.include?(:tries))
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
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, token, from, created_at, received_at, timeout, version = [VERSION, VERSION], size = nil)
      @identity    = identity
      @token       = token
      @from        = from
      @created_at  = created_at
      @received_at = received_at
      @timeout     = timeout
      @version     = version
      @size        = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Result):: New packet
    def self.create(o)
      i = o['data']
      new(self.compatible(i['identity']), i['token'], self.compatible(i['from']), i['created_at'],
          i['received_at'], i['timeout'], i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      log_msg = "#{super(filter, version)} #{trace} #{id_to_s(@identity)}"
      log_msg += " from #{id_to_s(@from)} created_at #{@created_at.to_i}"
      log_msg += " received_at #{@received_at.to_i} timeout #{@timeout}"
      log_msg
    end

  end # Stale


  # Deprecated for instance agents that are version 10 and above
  #
  # Packet for availability notification from an agent to the mappers
  class Register < Packet

    attr_accessor :identity, :services, :tags, :brokers, :shared_queue, :created_at

    # Create packet
    #
    # === Parameters
    # identity(String):: Sender identity
    # services(Array):: List of services provided by the node
    # tags(Array(Symbol)):: List of tags associated with this service
    # brokers(Array|nil):: Identity of agent's brokers with nil meaning not supported
    # shared_queue(String):: Name of a queue shared between this agent and another
    # created_at(Fixnum):: Time in seconds in Unix-epoch when this registration was created
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, services, tags, brokers, shared_queue = nil, created_at = nil,
                   version = [VERSION, VERSION], size = nil)
      @tags         = tags
      @brokers      = brokers
      @identity     = identity
      @services     = services
      @shared_queue = shared_queue
      @created_at   = created_at || Time.now.to_f
      @version      = version
      @size         = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Register):: New packet
    def self.create(o)
      i = o['data']
      if version = i['version']
        version = [version, version] unless version.is_a?(Array)
      else
        version = [DEFAULT_VERSION, DEFAULT_VERSION]
      end
      new(self.compatible(i['identity']), i['services'], i['tags'], i['brokers'], i['shared_queue'],
          i['created_at'], version, o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      log_msg = "#{super(filter, version)} #{id_to_s(@identity)}"
      log_msg += ", shared_queue #{@shared_queue}" if @shared_queue
      log_msg += ", services #{@services.inspect}" if @services && !@services.empty?
      log_msg += ", brokers #{@brokers.inspect}" if @brokers && !@brokers.empty?
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty?
      log_msg
    end

  end # Register


  # Deprecated for instance agents that are version 10 and above
  #
  # Packet for unregistering an agent from the mappers
  class UnRegister < Packet

    attr_accessor :identity

    # Create packet
    #
    # === Parameters
    # identity(String):: Sender identity
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, version = [VERSION, VERSION], size = nil)
      @identity = identity
      @version  = version
      @size     = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (UnRegister):: New packet
    def self.create(o)
      i = o['data']
      new(self.compatible(i['identity']), i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end
  
    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      "#{super(filter, version)} #{id_to_s(@identity)}"
    end

  end # UnRegister


  # Packet for requesting an agent to advertise its services to the mappers
  # when it initially comes online
  class Advertise < Packet

    # Create packet
    #
    # === Parameters
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(version = [VERSION, VERSION], size = nil)
      @version = version
      @size    = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Advertise):: New packet
    def self.create(o)
      i = o['data']
      new(i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

  end # Advertise


  # Packet for carrying statistics
  class Stats < Packet

    attr_accessor :data, :token, :from

    # Create packet
    #
    # === Parameters
    # data(Object):: Data
    # from(String):: Identity of sender
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(data, from, version = [VERSION, VERSION], size = nil)
      @data    = data
      @from    = from
      @version = version
      @size    = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Result):: New packet
    def self.create(o)
      i = o['data']
      new(i['data'], self.compatible(i['from']), i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      log_msg = "#{super(filter, version)} #{id_to_s(@from)}"
    end

  end # Stats


  # Deprecated for agents that are version 8 and above
  # instead use /mapper/update_tags
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
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(identity, new_tags, obsolete_tags, version = [VERSION, VERSION], size = nil)
      @identity      = identity
      @new_tags      = new_tags
      @obsolete_tags = obsolete_tags
      @version       = version
      @size          = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (TagUpdate):: New packet
    def self.create(o)
      i = o['data']
      new(self.compatible(i['identity']), i['new_tags'], i['obsolete_tags'],
          i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      log_msg = "#{super(filter, version)} #{id_to_s(@identity)}"
      log_msg += ", new tags #{@new_tags.inspect}" if @new_tags && !@new_tags.empty?
      log_msg += ", obsolete tags #{@obsolete_tags.inspect}" if @obsolete_tags && !@obsolete_tags.empty?
      log_msg
    end

  end # TagUpdate


  # Deprecated for agents that are version 8 and above
  # instead use Request of type /mapper/query_tags with :tags and :agent_ids in payload
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
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(from, opts, version = [VERSION, VERSION], size = nil)
      @from       = from
      @token      = opts[:token]
      @agent_ids  = opts[:agent_ids]
      @tags       = opts[:tags]
      @persistent = opts[:persistent]
      @version    = version
      @size       = size
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (TagQuery):: New packet
    def self.create(o)
      i = o['data']
      agent_ids = i['agent_ids'].map { |id| self.compatible(id) } if i['agent_ids']
      new(i['from'], { :token => i['token'], :agent_ids => agent_ids,
                       :tags => i['tags'],   :persistent => i['persistent'] },
          i['version'] || [DEFAULT_VERSION, DEFAULT_VERSION], o['size'])
    end

    # Generate log representation
    #
    # === Parameters
    # filter(Array(Symbol)):: Attributes to be included in output
    # version(Symbol|nil):: Version to display: :recv_version, :send_version, or nil meaning none
    #
    # === Return
    # log_msg(String):: Log representation
    def to_s(filter = nil, version = nil)
      log_msg = "#{super(filter, version)} #{trace}"
      log_msg += " from #{id_to_s(@from)}" if filter.nil? || filter.include?(:from)
      log_msg += " agent_ids #{@agent_ids.inspect}"
      log_msg += " tags #{@tags.inspect}"
      log_msg
    end

  end # TagQuery

end # RightScale

