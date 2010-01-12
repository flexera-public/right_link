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

  # This class allows sending requests to nanite agents without having
  # to run a local mapper.
  # It is used by Actor.request which can be used by actors than need
  # to send requests to remote agents.
  # All requests go through the mapper for security purposes.
  class MapperProxy
        
    $:.push File.dirname(__FILE__)
    require 'amqp'
  
    include AMQPHelper
    
    attr_accessor :pending_requests, :identity, :options, :amqp, :serializer

    # Accessor for actor
    def self.instance
      @@instance if defined?(@@instance)
    end

    def initialize(id, opts)
      @options = opts || {}
      @identity = id
      @pending_requests = {}
      @amqp = start_amqp(options)
      @serializer = Serializer.new(options[:format])
      @@instance = self
    end

    # Send request to given agent through the mapper
    def request(type, payload = '', opts = {}, &blk)
      raise "Mapper proxy not initialized" unless identity && options
      request = RequestPacket.new(type, payload, opts)
      request.from = identity
      request.token = AgentIdentity.generate
      request.persistent = opts.key?(:persistent) ? opts[:persistent] : options[:persistent]
      pending_requests[request.token] = { :result_handler => blk }
      RightLinkLog.info("SEND #{request.to_s([:tags, :target])}")
      amqp.fanout('request', :no_declare => options[:secure]).publish(serializer.dump(request))
    end    

    # Send push to given agent through the mapper
    def push(type, payload = '', opts = {})
      raise "Mapper proxy not initialized" unless identity && options
      push = PushPacket.new(type, payload, opts)
      push.from = identity
      push.token = AgentIdentity.generate
      push.persistent = opts.key?(:persistent) ? opts[:persistent] : options[:persistent]
      RightLinkLog.info("SEND #{push.to_s([:tags, :target])}")
      amqp.fanout('request', :no_declare => options[:secure]).publish(serializer.dump(push))
    end

    # Send tag query to mapper
    def query_tags(opts, &blk)
      raise "Mapper proxy not initialized" unless identity && options
      tag_query = TagQueryPacket.new(identity, opts)
      tag_query.token = AgentIdentity.generate
      tag_query.persistent = opts.key?(:persistent) ? opts[:persistent] : options[:persistent]      
      pending_requests[tag_query.token] = { :result_handler => blk }
      RightLinkLog.info("SEND #{tag_query.to_s}")
      amqp.fanout('request', :no_declare => options[:secure]).publish(serializer.dump(tag_query))
    end

    # Update tags registered by mapper for agent
    def update_tags(new_tags, obsolete_tags)
      raise "Mapper proxy not initialized" unless identity && options
      update = TagUpdatePacket.new(identity, new_tags, obsolete_tags)
      RightLinkLog.info("SEND #{update.to_s}")
      amqp.fanout('registration', :no_declare => options[:secure]).publish(serializer.dump(update))
    end

    # Handle final result
    def handle_result(res)
      handlers = pending_requests.delete(res.token)
      handlers[:result_handler].call(res) if handlers && handlers[:result_handler]
    end

  end # MapperProxy

end # RightScale
