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
      @size = msg.size
      msg.sub!(/size\300/) { |m| "size" + @size.to_msgpack }
      msg
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
      @size = js.size
      js = js.chop + ",\"size\":#{@size}}"
    end

    # Name of packet in lower snake case
    #
    # === Return
    # (String):: Packet name
    def name
       self.class.to_s.split('::').last.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').downcase
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
      log_msg = "[#{name}#{v}]"
      duration = ", #{enough_precision(@duration)} sec" if @duration && (filter.nil? || filter.include?(:duration))
      log_msg += " (#{@size.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")} bytes#{duration})" if @size && !@size.to_s.empty?
      log_msg
    end

    # Determine enough precision for floating point value to give at least two significant
    # digits and then convert the value to a decimal digit string of that precision
    #
    # === Parameters
    # value(Float):: Value to be converted
    #
    # === Return
    # (String):: Floating point digit string
    def enough_precision(value)
      scale = [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0]
      enough = lambda { |v| (v >= 10.0   ? 0 :
                            (v >= 1.0    ? 1 :
                            (v >= 0.1    ? 2 :
                            (v >= 0.01   ? 3 :
                            (v >  0.001  ? 4 :
                            (v >  0.0    ? 5 : 0)))))) }
      digit_str = lambda { |p, v| sprintf("%.#{p}f", (v * scale[p]).round / scale[p])}
      digit_str.call(enough.call(value), value)
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

    # Whether the packet is one that does not have an associated response
    #
    # === Return
    # (Boolean):: Defaults to true
    def one_way
      true
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

    attr_accessor :from, :scope, :payload, :type, :token, :reply_to, :selector, :target, :persistent, :expires_at,
                  :tags, :tries

    DEFAULT_OPTIONS = {:selector => :any}

    # Create packet
    #
    # === Parameters
    # type(String):: Dispatch route for the request
    # payload(Any):: Arbitrary data that is transferred to actor
    # opts(Hash):: Optional settings:
    #   :from(String):: Sender identity
    #   :scope(Hash):: Define behavior that should be used to resolve tag based routing
    #   :token(String):: Generated request id that a mapper uses to identify replies
    #   :reply_to(String):: Identity of the node that actor replies to, usually a mapper itself
    #   :selector(Symbol):: Selector used to route the request: :any or :all, defaults to :any,
    #     :all deprecated for version 13 and above
    #   :target(String):: Target recipient
    #   :persistent(Boolean):: Indicates if this request should be saved to persistent storage
    #     by the AMQP broker
    #   :expires_at(Integer|nil):: Time in seconds in Unix-epoch when this request expires and
    #      is to be ignored by the receiver; value 0 means never expire; defaults to 0
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
      @selector   = :any if ["least_loaded", "random"].include?(@selector.to_s)
      @target     = opts[:target]
      @persistent = opts[:persistent]
      @expires_at = opts[:expires_at] || 0
      @tags       = opts[:tags] || []
      @tries      = opts[:tries] || []
      @version    = version
      @size       = size
    end

    # Test whether the request is being fanned out to multiple targets
    #
    # === Return
    # (Boolean):: true if is multicast, otherwise false
    def fanout?
      @selector.to_s == 'all'
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
      expires_at = if i.has_key?('created_at')
        created_at = i['created_at'].to_i
        created_at > 0 ? created_at + (15 * 60) : 0
      else
        i['expires_at']
      end
      new(i['type'], i['payload'], { :from       => self.compatible(i['from']), :scope      => i['scope'],
                                     :token      => i['token'],                 :reply_to   => self.compatible(i['reply_to']),
                                     :selector   => i['selector'],              :target     => self.compatible(i['target']),
                                     :persistent => i['persistent'],            :tags       => i['tags'],
                                     :expires_at => expires_at,                 :tries      => i['tries'] },
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
      log_msg += ", fanout" if (filter.nil? || filter.include?(:fanout)) && fanout?
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
      @tries.map { |t| "<#{t}>" }.join(", ")
    end

    # Get target to be used for encrypting the packet
    #
    # === Return
    # (String):: Target
    def target_for_encryption
      @target
    end

    # Whether the packet is one that does not have an associated response
    #
    # === Return
    # false:: Always return false
    def one_way
      false
    end

  end # Request


  # Packet for a work request for an actor node that has no result, i.e., one-way request
  class Push < Packet

    attr_accessor :from, :scope, :payload, :type, :token, :selector, :target, :persistent, :expires_at, :tags

    DEFAULT_OPTIONS = {:selector => :any}

    # Create packet
    #
    # === Parameters
    # type(String):: Dispatch route for the request
    # payload(Any):: Arbitrary data that is transferred to actor
    # opts(Hash):: Optional settings:
    #   :from(String):: Sender identity
    #   :scope(Hash):: Define behavior that should be used to resolve tag based routing
    #   :token(String):: Generated request id that a mapper uses to identify replies
    #   :selector(Symbol):: Selector used to route the request: :any or :all, defaults to :any
    #   :target(String):: Target recipient
    #   :persistent(Boolean):: Indicates if this request should be saved to persistent storage
    #     by the AMQP broker
    #   :expires_at(Integer|nil):: Time in seconds in Unix-epoch when this request expires and
    #      is to be ignored by the receiver; value 0 means never expire; defaults to 0
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
      @selector   = :any if ["least_loaded", "random"].include?(@selector.to_s)
      @target     = opts[:target]
      @persistent = opts[:persistent]
      @expires_at = opts[:expires_at] || 0
      @tags       = opts[:tags] || []
      @version    = version
      @size       = size
    end

    # Test whether the request is being fanned out to multiple targets
    #
    # === Return
    # (Boolean):: true if is fanout, otherwise false
    def fanout?
      @selector.to_s == 'all'
    end

    # Keep interface consistent with Request packets
    # A push never gets retried
    #
    # === Return
    # []:: Always return empty array
    def tries
      []
    end

    # Create packet from unmarshalled data
    #
    # === Parameters
    # o(Hash):: Unmarshalled data
    #
    # === Return
    # (Push):: New packet
    def self.create(o)
      i = o['data']
      expires_at = if i.has_key?('created_at')
        created_at = i['created_at'].to_i
        created_at > 0 ? created_at + (15 * 60) : 0
      else
        i['expires_at']
      end
      new(i['type'], i['payload'], { :from   => self.compatible(i['from']),   :scope      => i['scope'],
                                     :token  => i['token'],                   :selector   => i['selector'],
                                     :target => self.compatible(i['target']), :persistent => i['persistent'],
                                     :tags   => i['tags'],                    :expires_at => expires_at },
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
      log_msg += ", fanout" if (filter.nil? || filter.include?(:fanout)) && fanout?
      log_msg += ", tags #{@tags.inspect}" if @tags && !@tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", persistent" if @persistent && (filter.nil? || filter.include?(:persistent))
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

    attr_accessor :token, :results, :to, :from, :request_from, :tries, :persistent, :duration

    # Create packet
    #
    # === Parameters
    # token(String):: Generated request id that a mapper uses to identify replies
    # to(String):: Identity of the node to which result should be delivered
    # results(Any):: Arbitrary data that is transferred from actor, a result of actor's work
    # from(String):: Sender identity
    # request_from(String):: Identity of the agent that sent the original request
    # tries(Array):: List of tokens for previous attempts to send associated request
    # persistent(Boolean):: Indicates if this result should be saved to persistent storage
    #   by the AMQP broker
    # duration(Float):: Number of seconds required to produce the result
    # version(Array):: Protocol version of the original creator of the packet followed by the
    #   protocol version of the packet contents to be used when sending
    # size(Integer):: Size of request in bytes used only for marshalling
    def initialize(token, to, results, from, request_from = nil, tries = nil, persistent = nil, duration = nil,
                   version = [VERSION, VERSION], size = nil)
      @token        = token
      @to           = to
      @results      = results
      @from         = from
      @request_from = request_from
      @tries        = tries || []
      @persistent   = persistent
      @duration     = duration
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
          self.compatible(i['request_from']), i['tries'], i['persistent'], i['duration'],
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
          if @results.is_a?(RightScale::OperationResult)   # Will be true when logging a 'SEND'
            res = @results
          elsif @results.is_a?(Hash) && @results.size == 1 # Will be true when logging a 'RECV' for version 9 or below
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

end # RightScale

