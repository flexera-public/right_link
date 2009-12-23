require 'redis'
require 'redis_tag_store'

module Nanite
  class State
    include Enumerable
    
    # This class encapsulates the state of a nanite system using redis as the 
    # data store and a provided tag store. For a nanite with the identity
    # 'nanite-foobar' we store the following:
    #
    # nanite-foobar: 0.72        # load average or 'status'
    # t-nanite-foobar: 123456789 # unix timestamp of the last state update
    #
    # The tag store is used to store the associated services and tags.
    #
    # A tag store should provide the following methods:
    #  - initialize(redis): Initialize tag store, may use provided redis handle
    #  - services(nanite): Retrieve services implemented by given agent
    #  - tags(nanite): Retrieve tags implemented by given agent
    #  - all_services: Retrieve all services implemented by all agents
    #  - all_tags: Retrieve all tags exposed by all agents
    #  - store(nanite, services, tags): Store agent's services and tags
    #  - update(name, new_tags,obsolete_tags): Update agent's tags
    #  - delete(nanite): Delete all entries associated with given agent
    #  - nanites_for(service, tags): Retrieve agents implementing given service
    #                                and exposing given tags
    #
    # The default implementation for the tag store reuses Redis.
  
    def initialize(redis, tag_store=nil)
      host, port, tag_store_type = redis.split(':')
      host ||= '127.0.0.1'
      port ||= '6379'
      tag_store||= 'Nanite::RedisTagStore'
      @redis = Redis.new(:host => host, :port => port)
      @tag_store = tag_store.to_const.new(@redis)
      Nanite::Log.info("[setup] Initializing redis state using host '#{host}', port '#{port}' and tag store #{tag_store}")
    end

    # Retrieve given agent services, tags, status and timestamp
    def [](nanite)
      log_redis_error do
        status    = @redis[nanite]
        timestamp = @redis["t-#{nanite}"]
        services  = @tag_store.services(nanite)
        tags      = @tag_store.tags(nanite)
        return nil unless status && timestamp && services
        {:services => services, :status => status, :timestamp => timestamp.to_i, :tags => tags}
      end
    end

    # Set given attributes for given agent
    # Attributes may include services, tags and status
    def []=(nanite, attributes)
      @tag_store.store(nanite, attributes[:services], attributes[:tags])
      update_status(nanite, attributes[:status])
    end

    # Delete all information related to given agent
    def delete(nanite)
      @tag_store.delete(nanite)
      log_redis_error do
        @redis.delete(nanite)
        @redis.delete("t-#{nanite}")
      end
    end

    # Update status and timestamp for given agent
    def update_status(name, status)
      log_redis_error do
        @redis[name] = status
        @redis["t-#{name}"] = Time.now.utc.to_i
      end
    end

    # Update tags for given agent
    def update_tags(name, new_tags, obsolete_tags)
      @tag_store.update(name, new_tags, obsolete_tags)
    end

    # Return all registered agents
    def list_nanites
      log_redis_error do
        @redis.keys("nanite-*")
      end
    end

    # Number of registered agents
    def size
      list_nanites.size
    end

    # Iterate through all agents, yielding services, tags
    # status and timestamp keyed by agent name
    def each
      list_nanites.each do |nan|
        yield nan, self[nan]
      end
    end

    # Return agents that implement given service and expose
    # all given tags
    def nanites_for(request)
      res = {}
      @tag_store.nanites_ids_for(request).each do |nanite_id|
        if nanite = self[nanite_id]
          res[nanite_id] = nanite
        end
      end
      res
    end

    private

    # Helper method, catch and log errors
    def log_redis_error(&blk)
      blk.call
    rescue Exception => e
      Nanite::Log.warn("redis error in method: #{caller[0]}")
      raise e
    end
    
  end
end  