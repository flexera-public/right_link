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

    include Singleton

    # Maximum amount of seconds to wait before starting flushing queue
    # when disabling offline mode
    MAX_FLUSH_DELAY = 120 # 2 minutes

    # Amount of seconds that should be spent in offline mode before triggering
    # a reenroll vote
    VOTE_DELAY = 900 # 15 minutes

    # Maximum number of in-memory messages before triggering re-enroll vote
    MAX_QUEUED_MESSAGES = 1000
    
    # Initialize singleton instance
    def initialize
      @vote_count = 0
      @mode = :initializing
      @running = false
      @in_init = false
      @requests = []
    end

    # Is agent currently offline?
    #
    # === Return
    # offline(TrueClass|FalseClass):: true if agent is disconnected or not initialized
    def offline?
      offline = @mode == :offline || !@running
    end

    # Initialize request forwarder, should be called once
    # All requests sent prior to running 'init' are queued
    # Requests will be sent once init has run
    #
    # === Block
    # If a block is given it's executed before the offline queue is flushed
    # This allows sending initialization requests before queued requests are sent
    #
    # === Return
    # true:: Always return true
    def init
      unless @running
        @running = true
        @in_init = true
        yield if block_given?
        @in_init = false
        flush_queue unless @requests.empty? || @mode == :offline
        @mode = :online if @mode == :initializing
      end
    end

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
    def request(type, payload = '', opts = {}, &blk)
      if offline?
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
    def push(type, payload = '', opts = {})
      if offline?
        queue_request(:kind => :push, :type => type, :payload => payload, :options => opts)
      else
        MapperProxy.instance.push(type, payload, opts)
      end
      true
    end

    # Switch to Offline mode, in this mode requests are queued in memory
    # rather than sent to the mapper, idempotent
    #
    # === Return
    # true:: Always return true
    def enable_offline_mode
      RightLinkLog.info("[offline] Deconnection from broker detected, entering offline mode")
      RightLinkLog.info("[offline] Messages will be queued in memory until connection to broker is re-established")
      if offline?
        if @flushing
          # If we were in offline mode then switched back to online but are still in the
          # process of flushing the in memory queue and are now switching to offline mode
          # again then stop the flushing
          @stop_flush = true
        end
      else
        @requests = []
        @mode = :offline
        @vote_timer ||= EM::Timer.new(VOTE_DELAY) { vote(timer_trigger=true) }
      end
    end

    # Switch back to sending requests to mapper after in memory queue gets flushed, idempotent
    #
    # === Return
    # true:: Always return true
    def disable_offline_mode
      if offline?
        RightLinkLog.info("[offline] Connection to broker re-established")
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
    def vote(timer_trigger)
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
    def queue_request(request)
      @vote_count += 1 if @running
      vote(timer_trigger=false) if @vote_count >= MAX_QUEUED_MESSAGES
      if @in_init
        # We are in the initialization callback, requests should be put at the head of the queue
        @requests.unshift(request)
      else
        @requests << request
      end
      true
    end

    # Flush in memory queue of requests that were stored while in offline mode
    # Do this asynchronously to allow for agents to respond to requests
    # Once all in-memory requests have been flushed, switch off offline mode
    #
    # === Return
    # true:: Always return true
    def flush_queue
      if @stop_flush
        @stop_flush = false
        @flushing = false
      else
        RightLinkLog.info("[offline] Starting flushing of in-memory queue") unless @mode == :initializing
        request = @requests.shift
        case request[:kind]
        when :push
          MapperProxy.instance.push(request[:type], request[:payload], request[:options])
        when :request
          MapperProxy.instance.request(request[:type], request[:payload], request[:options], request[:callback])
        end
        if @requests.empty?
          RightLinkLog.info("[offline] In-memory queue flushed, resuming normal operations") unless @mode == :initializing
          @mode = :online
          @flushing = false
        else
          EM.next_tick { flush_queue }
        end
      end
    end

  end
end
