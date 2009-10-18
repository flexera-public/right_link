# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.

module RightScale
  
  # Agent identity management
  class AgentIdentity

    # Separator used to differentiate between identity components when serialized
    ID_SEPARATOR = '*'

    # Identity components
    attr_reader :prefix, :agent_name, :token, :base_id

    # Generate new id
    #
    # === Parameters
    # prefix<String>:: Prefix used to scope identity
    # agent_name<String>:: Name of agent (e.g. 'core', 'instance')
    # base_id<Integer>:: Unique integer value
    # token<String>:: Anonymizing token - Optional, will be generated randomly if not provided
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Invalid argument
    def initialize(prefix, agent_name, base_id, token=nil)
      err = "Prefix cannot contain '#{ID_SEPARATOR}'" if prefix && prefix.include?(ID_SEPARATOR)
      err = "Prefix cannot contain '-'" if prefix && prefix.include?('-')
      err = "Agent name cannot contain '#{ID_SEPARATOR}'" if agent_name.include?(ID_SEPARATOR)
      err = "Agent name cannot be nil" if agent_name.nil?
      err = "Agent name cannot be empty" if agent_name.size == 0
      err = "Base ID must be a positive integer" unless base_id.kind_of?(Integer) && base_id >= 0
      err = "Token cannot contain '#{ID_SEPARATOR}'" if token && token.include?(ID_SEPARATOR)
      raise RightScale::Exceptions::Argument, err if err

      @prefix     = prefix
      @agent_name = agent_name
      @token      = token || Nanite::Identity.generate
      @base_id    = base_id
    end
    
    # Check validity of given serialized identity
    #
    # === Parameters
    # serialized<String>:: Serialized identity to be tested
    #
    # === Return
    # true:: If serialized identity is a valid identity token
    # false:: Otherwise
    def self.valid?(serialized)
      return false unless serialized && serialized.respond_to?(:split)
      parts = serialized.split(ID_SEPARATOR)
      res = parts.size == 4   &&
            parts[1].size > 0 &&
            parts[2].size > 0 &&
            parts[3].to_i.to_s == parts[3]
    end
    
    # Instantiate by parsing given token
    #
    # === Parameters
    # serialized_id<String>:: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # id<RightScale::AgentIdentity>:: Corresponding agent identity
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Serialized agent identity is incorrect
    def self.parse(serialized_id)
      prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR)
      raise RightScale::Exceptions::Argument, "Invalid agent identity token" unless prefix && agent_name && token && bid
      base_id = bid.to_i
      raise RightScale::Exceptions::Argument, "Invalid agent identity token (Base ID)" unless base_id.to_s == bid
      prefix = prefix.split('-').last
      id = AgentIdentity.new(prefix, agent_name, base_id, token)
    end

    # Instantiate by parsing given nanite agent identity
    #
    # === Parameters
    # nanite<String>:: Nanite agent identity
    #
    # === Return
    # serialized<String>:: Serialized agent id from nanite id
    def self.serialized_from_nanite(nanite)
      serialized = nanite[7, nanite.length] # 'nanite-'.length == 7
    end

    # Generate nanite agent identity from serialized representation
    #
    # === Parameters
    # serialized<String>:: Serialized agent identity
    #
    # === Return
    # nanite<String>:: Corresponding nanite id
    def self.nanite_from_serialized(serialized)
      nanite = "nanite-#{serialized}"
    end

    # String representation of identity
    #
    # === Return
    # serialized<String>:: Serialized identity
    def to_s
      serialized = "#{@prefix}#{ID_SEPARATOR}#{@agent_name}#{ID_SEPARATOR}#{token}#{ID_SEPARATOR}#{@base_id}"
    end

    # Comparison operator
    #
    # === Parameters
    # other<AgentIdentity>:: Other agent identity
    #
    # === Return
    # true:: If other is identical to self
    # false:: Otherwise
    def ==(other)
      other.kind_of?(::RightScale::AgentIdentity) &&
      prefix     == other.prefix     &&
      agent_name == other.agent_name &&
      token      == other.token      &&
      base_id    == other.base_id
    end
  
  end
end
