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

  class RequestForwarder

    # Maximum amount of seconds to wait before starting flushing queue
    # when disabling offline mode
    MAX_FLUSH_DELAY = 900 # 15 minutes

    # Amount of seconds that should be spent in offline mode before triggering
    # a reenroll vote
    VOTE_DELAY = 3600 # 1 hour

    # Maximum number of in-memory messages before triggering re-enroll vote
    MAX_QUEUED_MESSAGES = 1000

    # Send request or buffer it if we are in offline mode
    #
    # === Parameters
    # type(String):: Request service (e.g. '/booter/set_r_s_version')
    # payload(String):: Associated payload, optional
    # opts(Hash):: Options as allowed by Request packet, optional
    #
    # === Block
    # Handler block gets called back with request results
    #
    # === Return
    # true:: Always return true
    def self.request(type, payload = '', opts = {}, &blk)
      if @offline_mode
        queue_request(:kind => :request, :type => type, :payload => payload, :options => opts, :callback => blk)
      else
        MapperProxy.instance.request(type, payload, opts, &blk)
      end
      true
    end

    # Send push or buffer it if we are in offline mode
    #
    # === Parameters
    # type(String):: Request service (e.g. '/booter/set_r_s_version')
    # payload(String):: Associated payload, optional
    # opts(Hash):: Options as allowed by Push packet, optional
    #
    # === Return
    # true:: Always return true
    def self.push(type, payload = '', opts = {})
      if @offline_mode
        queue_request(:kind => :push, :type => type, :payload => payload, :options => opts)
      else
        MapperProxy.instance.push(type, payload, opts)
      end
      true
    end

    # Send tag query or buffer it if we are in offline mode
    #
    # === Parameters
    # opts(Hash):: Hash containing tags and agent ids used for query
    #
    # === Block
    # Handler block gets called back with query results
    #
    # === Return
    # true:: Always return true
    def self.query_tags(opts = {}, &blk)
      if @offline_mode
        queue_request(:kind => :tag_query, :options => opts, :callback => blk)
      else
        MapperProxy.instance.query_tags(opts, &blk)
      end
      true
    end

    # Switch to Offline mode, in this mode requests are queued in memory
    # rather than sent to the mapper, idempotent
    #
    # === Return
    # true:: Always return true
    def self.enable_offline_mode
      if @offline_mode
        if @flushing
          # If we were in offline mode then switched back to online but are still in the
          # process of flushing the in memory queue and are now switching to offline mode
          # again then stop the flushing
          @stop_flush = true
        end
      else
        @requests = []
        @offline_mode = true
        @vote_timer ||= EM::Timer.new(VOTE_DELAY) { vote(timer_trigger=true) }
      end
    end

    # Switch back to sending requests to mapper after in memory queue gets flushed, idempotent
    #
    # === Return
    # true:: Always return true
    def self.disable_offline_mode
      if @offline_mode
        @vote_timer.cancel if @vote_timer
        @vote_timer = nil
        @stop_flush = false
        @flushing = true
        # Let's wait a bit not to flood the mapper
        EM.add_timer(rand(MAX_FLUSH_DELAY)) { flush_queue }
      end
      true
    end

    protected

    # Vote for re-enrollment and reset trigger
    #
    # === Parameters
    # timer_trigger(Boolean):: true if vote was triggered by timer, false if it
    #                          was triggered by amount of messages in in-memory queue
    def self.vote(timer_trigger)
      RightScale::ReenrollManager.vote
      if timer_trigger
        @vote_timer = EM::Timer.new(VOTE_DELAY) { vote(timer_trigger=true) }
      else
        @vote_count = 0
      end
    end

    # Queue given request/push in-memory
    #
    # === Parameters
    # request(Hash):: Request/push to be stored as a hash
    #
    # === Return
    # true:: Always return true
    def self.queue_request(request)
      @vote_count ||= 0
      @vote_count += 1
      vote(timer_trigger=false) if @vote_count >= MAX_QUEUED_MESSAGES
      @requests << request
      true
    end

    # Flush in memory queue of requests that were stored while in offline mode
    # Do this asynchronously to allow for agents to respond to requests
    # Once all in-memory requests have been flushed, switch off offline mode
    #
    # === Return
    # true:: Always return true
    def self.flush_queue
      if @stop_flush
        @stop_flush = false
        @flushing = false
      else
        request = @requests.shift
        case request[:kind]
        when :push
          MapperProxy.instance.push(request[:type], request[:payload], request[:options])
        when :request
          MapperProxy.instance.request(request[:type], request[:payload], request[:options], request[:callback])
        when :tag_query
          MapperProxy.instance.query_tags(request[:options], request[:callback])
        end
        if @requests.empty?
          @offline_mode = false
          @flushing = false
        else
          EM.next_tick { flush_queue }
        end
      end
    end

  end
end
