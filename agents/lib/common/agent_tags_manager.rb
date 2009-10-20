# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.

module RightScale

  # Agent tags management
  class AgentTagsManager

    # Singleton instance accessor
    def self.instance
      @@instance if defined?(@@instance)
    end

    # Initialize manager
    #
    # === Parameters
    # agent<Nanite::Agent>:: Tags owner agent
    def initialize(agent)
      @agent = agent
      @@instance = self
    end

    # Retrieve current agent tags
    #
    # === Return
    # tags<Array>:: All agent tags
    def tags
      tags = @agent.tags
    end

    # Add given tags to agent
    #
    # === Parameters
    # new_tags<Array>:: Tags to be added
    #
    # === Return
    # true always return true
    def add_tags(*new_tags)
      @agent.update_tags(new_tags, [])
      true
    end

    # Remove given tags from agent
    #
    # === Parameters
    # old_tags<Array>:: Tags to be removed
    #
    # === Return
    # true always return true
    def remove_tags(*old_tags)
      @agent.update_tags([], old_tags)
      true
    end

    # Clear all agent tags
    #
    # === Return
    # true::Always return true
    def clear
      @agent.update_tags([], tags)
      true
    end

  end
end
