require 'redis'

module Nanite

  # Implementation of a tag store on top of Redis
  # For a nanite with the identity 'nanite-foobar', we store the following:
  #
  # s-nanite-foobar: { /foo/bar, /foo/nik } # a SET of the provided services
  # tg-nanite-foobar: { foo-42, customer-12 } # a SET of the tags for this agent
  #
  # Also we do an inverted index for quick lookup of agents providing a certain
  # service, so for each service the agent provides, we add the nanite to a SET
  # of all the nanites that provide said service:
  #
  # foo/bar: { nanite-foobar, nanite-nickelbag, nanite-another } # redis SET
  #
  # We do that same thing for tags:
  #
  # some-tag: { nanite-foobar, nanite-nickelbag, nanite-another } # redis SET
  #
  # This way we can do a lookup of what nanites provide a set of services and tags based
  # on redis SET intersection:
  #
  # nanites_for('/gems/list', 'some-tag')
  # => returns an array of nanites that provide the intersection of these two service tags

  class RedisTagStore

    # Initialize tag store with given redis handle
    def initialize(redis)
      @redis = redis
    end

    # Store services and tags for given agent
    def store(nanite, services, tags)
      services = nil if services.compact.empty?
      tags = nil if tags.compact.empty?
      log_redis_error do
        if services
          obsolete_services = @redis.set_members("s-#{nanite}") - services
          update_elems(nanite, services, obsolete_services, "s-#{nanite}", 'naniteservices')
        end
        if tags
          obsolete_tags = @redis.set_members("tg-#{nanite}") - tags
          update_elems(nanite, tags, obsolete_tags, "tg-#{nanite}", 'nanitestags')
        end
      end
    end

    # Update tags for given agent
    def update(nanite, new_tags, obsolete_tags)
      update_elems(nanite, new_tags, obsolete_tags, "tg-#{nanite}", 'nanitestags')
    end

    # Delete services and tags for given agent
    def delete(nanite)
      delete_elems(nanite, "s-#{nanite}", 'naniteservices')
      delete_elems(nanite, "tg-#{nanite}", 'nanitestags')
    end

    # Services implemented by given agent
    def services(nanite)
      @redis.set_members("s-#{nanite}")
    end

    # Tags exposed by given agent
    def tags(nanite)
      @redis.set_members("tg-#{nanite}")
    end

    # Retrieve nanites implementing given service and exposing given tags
    def nanites_ids_for(request)
      keys = request.tags ? request.tags.dup : []
      keys << request.type if request.type
      keys.compact!
      return {} if keys.empty?
      log_redis_error { @redis.set_intersect(keys) }
    end

    private

    # Update values stored for given agent
    # Also store reverse lookup information using both a unique and
    # a global key (so it's possible to retrieve that agent value or
    # all related values)
    def update_elems(nanite, new_tags, obsolete_tags, elem_key, global_key)
      new_tags = nil if new_tags.compact.empty?
      obsolete_tags = nil if obsolete_tags.compact.empty?
      log_redis_error do
        obsolete_tags.each do |val|
          @redis.set_delete(val, nanite)
          @redis.set_delete(elem_key, val)
          @redis.set_delete(global_key, val)
        end if obsolete_tags
        new_tags.each do |val|
          @redis.set_add(val, nanite)
          @redis.set_add(elem_key, val)
          @redis.set_add(global_key, val)
        end if new_tags
      end
    end

    # Delete all values for given nanite agent
    # Also delete reverse lookup information
    def delete_elems(nanite, elem_key, global_key)
      log_redis_error do
        (@redis.set_members(elem_key)||[]).each do |val|
          @redis.set_delete(val, nanite)
          if @redis.set_count(val) == 0
            @redis.delete(val)
            @redis.set_delete(global_key, val)
          end
        end
        @redis.delete(elem_key)
      end
    end

    # Helper method, catch and log errors
    def log_redis_error(&blk)
      blk.call
    rescue Exception => e
      Nanite::Log.warn("redis error in method: #{caller[0]}")
      raise e
    end

  end
end
