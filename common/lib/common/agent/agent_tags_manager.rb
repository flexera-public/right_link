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

    # synchronous tag requests need a long timeout
    TAG_REQUEST_TIMEOUT = 2 * 60

    # Retrieve current agent tags and give result to block
    #
    # === Block
    # Given block should take one argument which will be set with an array
    # initialized with the tags of this instance
    #
    # === Return
    # true:: Always return true
    def tags
      do_query do |result|
        tags = (result.size == 1 ? result.values.first['tags'] : [])
        yield tags
      end
    end

    # Queries a list of servers in the current deployment which have one or more
    # of the given tags.
    #
    # === Parameters
    # tags(Array):: tags to query or empty
    #
    # === Block
    # Given block should take one argument which will be set with an array
    # initialized with the tags of this instance
    #
    # === Return
    # true:: Always return true
    def query_tags(*tags)
      do_query(tags) { |result| yield result }
    end

    # Queries a list of servers in the current deployment which have one or more
    # of the given tags. Yields the raw response (for responding locally).
    #
    # === Parameters
    # tags(Array):: tags to query or empty
    #
    # === Block
    # Given block should take one argument which will be set with the raw response
    #
    # === Return
    # true:: Always return true
    def query_tags_raw(*tags)
      do_query(tags, true) { |raw_response| yield raw_response }
    end

    # Add given tags to agent
    #
    # === Parameters
    # new_tags(Array):: Tags to be added
    #
    # === Block
    # Given block should take one argument which will be set with the raw response
    #
    # === Return
    # true always return true
    def add_tags(*new_tags)
      update_tags(new_tags, []) { |raw_response| yield raw_response }
    end

    # Remove given tags from agent
    #
    # === Parameters
    # old_tags(Array):: Tags to be removed
    #
    # === Block
    # Given block should take one argument which will be set with the raw response
    #
    # === Return
    # true always return true
    def remove_tags(*old_tags)
      update_tags([], old_tags) { |raw_response| yield raw_response }
    end

    # Runs a tag update with a list of new and old tags.
    #
    # === Parameters
    # new_tags(Array):: new tags to add or empty
    # old_tags(Array):: old tags to remove or empty
    # block(Block):: optional callback for update response
    #
    # === Block
    # Given block should take one argument which will be set with the raw response
    #
    # === Return
    # true:: Always return true
    def update_tags(new_tags, old_tags, &block)
      agent_check
      tags = @agent.tags
      tags += (new_tags || [])
      tags -= (old_tags || [])
      tags.uniq!

      request = RightScale::IdempotentRequest.new("/mapper/update_tags",
                                                  {:new_tags => new_tags, :obsolete_tags => old_tags},
                                                  {:timeout => TAG_REQUEST_TIMEOUT})
      if block
        # always yield raw response
        request.callback do |_|
          # refresh agent's copy of tags on successful update
          @agent.tags = tags
          block.call(request.raw_response)
        end
        request.errback { |_| block.call(request.raw_response) }
      end
      request.run
      true
    end

    # Clear all agent tags
    #
    # === Block
    # Given block should take one argument which will be set with the raw response
    #
    # === Return
    # true::Always return true
    def clear
      update_tags([], tags) { |raw_response| yield raw_response }
    end

    private

    def agent_check
      raise ArgumentError, "Must set agent= before using tag manager" unless @agent
    end

    # Runs a tag query with an optional list of tags.
    #
    # === Parameters
    # tags(Array):: tags to query or empty
    # raw(Boolean):: true to yield raw tag response instead of deserialized tags
    #
    # === Block
    # Given block should take one argument which will be set with an array
    # initialized with the tags of this instance
    #
    # === Return
    # true:: Always return true
    def do_query(tags = nil, raw = false)
      agent_check
      payload = {:agent_ids => [@agent.identity]}
      payload[:tags] = tags unless tags.nil? || tags.empty?
      request = RightScale::IdempotentRequest.new("/mapper/query_tags",
                                                  payload,
                                                  {:timeout => TAG_REQUEST_TIMEOUT})
      request.callback { |result| yield raw ? request.raw_response : result }
      request.errback do |message|
        RightScale::RightLinkLog.error("Failed to query tags: #{message}")
        yield request.raw_response if raw
      end
      request.run
      true
    end

  end
end
