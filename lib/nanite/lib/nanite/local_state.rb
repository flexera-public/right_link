module Nanite
  class LocalState < ::Hash
    def initialize(hsh={})
      hsh.each do |k,v|
        self[k] = v
      end
    end

    def nanites_for(request)
      tags = request.tags
      service = request.type
      if service
        nanites = reject { |_, state| !state[:services].include?(service) }
      else
        nanites = self
      end

      if tags.nil? || tags.empty?
        service ? nanites : {}
      else
        nanites.reject { |_, state| (state[:tags] & tags).empty? }
      end
    end

    def update_status(name, status)
      self[name].update(:status => status, :timestamp => Time.now.utc.to_i)
    end
    
    def update_tags(name, new_tags, obsolete_tags)
      prev_tags = self[name] && self[name][:tags]
      updated_tags = (new_tags || []) + (prev_tags || []) - (obsolete_tags || [])
      self[name].update(:tags => updated_tags.uniq)
    end
    
    private

    def all(key)
      map { |n,s| s[key] }.flatten.uniq.compact
    end

  end # LocalState
end # Nanite
