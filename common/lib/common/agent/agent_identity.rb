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
  
  # Agent identity management
  class AgentIdentity
    # Cutover time at which agents began using new separator
    SEPARATOR_EPOCH = Time.at(1256702400) unless defined?(SEPARATOR_EPOCH) #Tue Oct 27 21:00:00 -0700 2009

    # Separator used to differentiate between identity components when serialized
    ID_SEPARATOR = '-' unless defined?(ID_SEPARATOR)

    # Separator used to differentiate between identity components prior to release 3.4
    ID_SEPARATOR_OLD = '*' unless defined?(ID_SEPARATOR_OLD)

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
    def initialize(prefix, agent_name, base_id, token=nil, delimeter=nil)
      err = "Prefix cannot contain '#{ID_SEPARATOR}'" if prefix && prefix.include?(ID_SEPARATOR)
      err = "Prefix cannot contain '#{ID_SEPARATOR_OLD}'" if prefix && prefix.include?(ID_SEPARATOR_OLD)
      err = "Agent name cannot contain '#{ID_SEPARATOR}'" if agent_name.include?(ID_SEPARATOR)
      err = "Agent name cannot contain '#{ID_SEPARATOR_OLD}'" if agent_name.include?(ID_SEPARATOR_OLD)
      err = "Agent name cannot be nil" if agent_name.nil?
      err = "Agent name cannot be empty" if agent_name.size == 0
      err = "Base ID must be a positive integer" unless base_id.kind_of?(Integer) && base_id >= 0
      err = "Token cannot contain '#{ID_SEPARATOR}'" if token && token.include?(ID_SEPARATOR)
      err = "Token cannot contain '#{ID_SEPARATOR_OLD}'" if token && token.include?(ID_SEPARATOR_OLD)
      raise RightScale::Exceptions::Argument, err if err

      @delimeter  = delimeter || ID_SEPARATOR
      @prefix     = prefix
      @agent_name = agent_name
      @token      = token || self.class.generate
      @base_id    = base_id
    end

    # Generate unique identity
    def self.generate
      values = [
        rand(0x0010000),
        rand(0x0010000),
        rand(0x0010000),
        rand(0x0010000),
        rand(0x0010000),
        rand(0x1000000),
        rand(0x1000000),
      ]
      "%04x%04x%04x%04x%04x%06x%06x" % values
    end

    # Check whether identity corresponds to an instance agent
    #
    # === Return
    # true:: If id corresponds to an instance agent
    # false:: Otherwise
    def instance_agent?
      agent_name == 'instance'
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
      return false unless serialized && serialized.respond_to?(:split) && serialized.respond_to?(:include?)
      serialized = serialized_from_nanite(serialized) if valid_nanite?(serialized)
      p = parts(serialized)

      res = p.size == 5 &&
            p[1] && p[1].size > 0 &&
            p[2] && p[2].size > 0 &&
            p[3] && p[3].to_i.to_s == p[3]
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
      serialized_id = serialized_from_nanite(serialized_id) if valid_nanite?(serialized_id)
      prefix, agent_name, token, bid, delimeter = parts(serialized_id)
      raise RightScale::Exceptions::Argument, "Invalid agent identity token" unless prefix && agent_name && token && bid
      base_id = bid.to_i
      raise RightScale::Exceptions::Argument, "Invalid agent identity token (Base ID)" unless base_id.to_s == bid

      id = AgentIdentity.new(prefix, agent_name, base_id, token, delimeter)
    end

    # Does given id correspond to an instance agent?
    #
    # === Parameters
    # serialized_id<String>:: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # true:: If given id corresponds to an instance agent
    # false:: Otherwise
    def self.instance_agent?(serialized_id)
      parts(serialized_id)[1] == 'instance'
    end

    # Check validity of nanite name. Checks whether this is a well-formed nanite name,
    # does NOT check validity of the ID itself.
    #
    # === Parameters
    # name<String>:: string to test for well-formedness
    #
    # === Return
    # true:: If name is a valid Nanite name (begins with "nanite-")
    # false:: Otherwise
    def self.valid_nanite?(name)
      !!(name =~ /^(nanite|mapper)-/)
    end

    # Instantiate by parsing given nanite agent identity
    #
    # === Parameters
    # nanite<String>:: Nanite agent identity
    #
    # === Return
    # serialized<String>:: Serialized agent id from nanite id
    def self.serialized_from_nanite(nanite)
      serialized = nanite[7..-1] # 'nanite-'.length == 7
    end

    # Generate agent identity from serialized representation
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
      serialized = "#{@prefix}#{@delimeter}#{@agent_name}#{@delimeter}#{@token}#{@delimeter}#{@base_id}"
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

    protected

    # Split given serialized id into its parts
    #
    # === Parameters
    # serialized_id<String>:: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # <Array>:: Array of parts: prefix, agent name, token, base id and delimeter
    def self.parts(serialized_id)
      prefix = agent_name = token = bid = delimeter = nil
      if serialized_id.include?(ID_SEPARATOR)
        prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR)
        delimeter = ID_SEPARATOR
      elsif serialized_id.include?(ID_SEPARATOR_OLD)
        prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR_OLD)
        delimeter = ID_SEPARATOR_OLD
      end
      [ prefix, agent_name, token, bid, delimeter ]
    end

  end
end
