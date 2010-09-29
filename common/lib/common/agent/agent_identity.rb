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
    # prefix(String):: Prefix used to scope identity
    # agent_name(String):: Name of agent (e.g. 'core', 'instance')
    # base_id(Integer):: Unique integer value
    # token(String):: Unique identity token, will be generated randomly if not provided
    # separator(String):: Character used to separate identity components, defaults to ID_SEPARATOR
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Invalid argument
    def initialize(prefix, agent_name, base_id, token=nil, separator=nil)
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

      @separator  = separator || ID_SEPARATOR
      @prefix     = prefix
      @agent_name = agent_name
      @token      = token || self.class.generate
      @base_id    = base_id
    end

    # Generate unique identity
    #
    # === Return
    # id(String):: Random 128-bit hexadecimal string
    def self.generate
      bytes = RightScale::RightLinkConfig[:platform].rng.pseudorandom_bytes(16)
      #Transform into hex string
      id = bytes.unpack('H*')[0]
    end

    # Check validity of given serialized identity
    #
    # === Parameters
    # serialized_id(String):: Serialized identity to be tested
    #
    # === Return
    # (Boolean):: true if serialized identity is a valid, otherwise false
    def self.valid?(serialized_id)
      valid_parts?(self.compatible_serialized(serialized_id)) if serialized_id
    end
    
    # Instantiate by parsing given token
    #
    # === Parameters
    # serialized_id(String):: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # (AgentIdentity):: Corresponding agent identity
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: Serialized agent identity is incorrect
    def self.parse(serialized_id)
      serialized_id = self.compatible_serialized(serialized_id)
      prefix, agent_name, token, bid, separator = parts(serialized_id)
      raise RightScale::Exceptions::Argument, "Invalid agent identity token" unless prefix && agent_name && token && bid
      base_id = bid.to_i
      raise RightScale::Exceptions::Argument, "Invalid agent identity token (Base ID)" unless base_id.to_s == bid

      AgentIdentity.new(prefix, agent_name, base_id, token, separator)
    end

    # Convert serialized agent identity to format valid for given protocol version
    # Ignore identity that is not in serialized AgentIdentity format
    #
    # === Parameters
    # serialized_id(String):: Serialized agent identity to be converted
    # version(Integer):: Target protocol version
    #
    # === Return
    # serialized_id(String):: Compatible serialized agent identity
    def self.compatible_serialized(serialized_id, version = 10)
      if version < 10
        serialized_id = "nanite-#{serialized_id}" if self.valid_parts?(serialized_id)
      else
        serialized_id = serialized_id[7..-1] if serialized_id =~ /^nanite-|^mapper-/
      end
      serialized_id
    end

    # Check whether identity corresponds to an instance agent
    #
    # === Return
    # (Boolean):: true if id corresponds to an instance agent, otherwise false
    def instance_agent?
      agent_name == 'instance'
    end

    # Check whether identity corresponds to an instance agent
    #
    # === Parameters
    # serialized_id(String):: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # (Boolean):: true if id corresponds to an instance agent, otherwise false
    def self.instance_agent?(serialized_id)
      parts(serialized_id)[1] == 'instance'
    end

    # String representation of identity
    #
    # === Return
    # (String):: Serialized identity
    def to_s
      "#{@prefix}#{@separator}#{@agent_name}#{@separator}#{@token}#{@separator}#{@base_id}"
    end

    # Comparison operator
    #
    # === Parameters
    # other(AgentIdentity):: Other agent identity
    #
    # === Return
    # (Boolean):: true if other is identical to self, otherwise false
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
    # serialized_id(String):: Valid serialized agent identity (use 'valid?' to check first)
    #
    # === Return
    # (Array):: Array of parts: prefix, agent name, token, base id and separator
    def self.parts(serialized_id)
      prefix = agent_name = token = bid = separator = nil
      if serialized_id.include?(ID_SEPARATOR)
        prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR)
        separator = ID_SEPARATOR
      elsif serialized_id.include?(ID_SEPARATOR_OLD)
        prefix, agent_name, token, bid = serialized_id.split(ID_SEPARATOR_OLD)
        separator = ID_SEPARATOR_OLD
      end
      [ prefix, agent_name, token, bid, separator ]
    end

    # Check that given serialized identity has valid parts
    #
    # === Parameters
    # serialized_id(String):: Serialized identity to be tested
    #
    # === Return
    # (Boolean):: true if serialized identity is a valid identity token, otherwise false
    def self.valid_parts?(serialized_id)
      p = parts(serialized_id)
      res = p.size == 5 &&
            p[1] && p[1].size > 0 &&
            p[2] && p[2].size > 0 &&
            p[3] && p[3].to_i.to_s == p[3]
    end

  end # AgentIdentity

end # RightScale
