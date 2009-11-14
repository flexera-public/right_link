# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.

require 'singleton'

module RightScale

  # Agent tags management
  class AgentTagsManager
    include Singleton

    attr_accessor :agent

    # Retrieve current agent tags
    #
    # === Return
    # tags<Array>:: All agent tags
    def tags
      raise TypeError, "Must set agent= before using tag manager" unless @agent
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
      raise TypeError, "Must set agent= before using tag manager" unless @agent
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
      raise TypeError, "Must set agent= before using tag manager" unless @agent
      @agent.update_tags([], old_tags)
      true
    end

    # Clear all agent tags
    #
    # === Return
    # true::Always return true
    def clear
      raise TypeError, "Must set agent= before using tag manager" unless @agent
      @agent.update_tags([], tags)
      true
    end

  end
end
