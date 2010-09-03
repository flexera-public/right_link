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

require 'singleton'

module RightScale

  # Agent tags management
  class AgentTagsManager
    include Singleton

    # (Agent) Agent being managed
    attr_accessor :agent

    # Retrieve current agent tags and give result to block, asynchronous
    #
    # === Block
    # Given block should take one argument which will be set with an array
    # initialized with the tags of this instance
    #
    # === Return
    # true:: Always return true
    def tags
      raise TypeError, "Must set agent= before using tag manager" unless @agent
      RightScale::RequestForwarder.instance.request("/mapper/tag_query", :agent_ids => [@agent.identity]) do |r|
        res = RightScale::OperationResult.from_results(r)
        if res.success?
          result = res.content
          tags = (result.size == 1 ? result[result.keys[0]]['tags'] : [])
          yield tags
        else
          RightScale::RightLinkLog.error("Failed to get identified server, got: #{res.content}")
        end
      end
      true
    end

    # Add given tags to agent
    #
    # === Parameters
    # new_tags(Array):: Tags to be added
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
    # old_tags(Array):: Tags to be removed
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
