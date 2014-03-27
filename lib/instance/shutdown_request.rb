#
# Copyright (c) 2011 RightScale Inc
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

  # Mixin for defining a common interface for a shutdown request class and its
  # proxy class.
  module ShutdownRequestMixin

    # initial kind; no shutdown requested.
    CONTINUE = 'continue'

    # requested a reboot.
    REBOOT = 'reboot'

    # requested a stop (keep boot volume after shutdown).
    STOP = 'stop'

    # requested a terminate (discard boot volume after shutdown).
    TERMINATE = 'terminate'

    # levels.
    LEVELS = [CONTINUE, REBOOT, STOP, TERMINATE]

    # exceptions.
    class NotInitialized < Exception; end
    class InvalidLevel < Exception; end


    # true if no shutdown was requested, false if shutdown was requested.
    def continue?; CONTINUE == @level; end

    # true if any requested shutdown will interrupt sequence of running scripts
    # immediately (current script is allowed to complete).
    # false to defer shutdown until all outstanding scripts have run.
    def immediately?; @immediately; end
    def immediately!
      raise InvalidLevel.new("Immediately is unexpected for current shutdown state") if continue?
      @immediately = true
    end

    # Shutdown request level.
    def level; @level; end
    def level=(value)
      value = value.to_s
      raise InvalidLevel.new("Invalid shutdown level: #{value.inspect}") unless LEVELS.include?(value)

      # strictly escalate to higher level and ignore lower level requests.
      @level = value if LEVELS.index(value) > LEVELS.index(@level)
    end

    # Stringizer.
    def to_s
      # note that printing 'deferred' would seem strange at the time when the
      # deferred shutdown is actually being processed, so only say immediately.
      immediacy = if @immediately; ' immediately'; else; ''; end
      return "#{@level}#{immediacy}"
    end

    protected

    def initialize
      @level = CONTINUE
      @immediately = false
    end

  end

  # Represents outstanding request(s) for reboot, stop or terminate instance.
  # Requests are cumulative and implicitly non-decreasing in level (e.g. reboot
  # never supersedes terminate).
  class ShutdownRequest

    include ShutdownRequestMixin

    # Class initializer.
    #
    # === Parameters
    # scheduler(InstanceScheduler):: scheduler for shutdown requests
    #
    # === Return
    # always true
    def self.init(scheduler)
      @@instance = ShutdownRequest.new
      @@scheduler = scheduler
      true
    end

    # Factory method
    #
    # === Return
    # (ShutdownRequest):: the singleton for this class
    def self.instance
      raise NotInitialized.new("ShutdownRequest.init has not been called") unless defined?(@@instance)
      return @@instance
    end

    # Submits a new shutdown request state which may be superceded by a
    # previous, higher-priority shutdown level.
    #
    # === Parameters
    # request[:level](String):: shutdown level
    # request[:immediately](Boolean):: shutdown immediacy or nil
    #
    # === Returns
    # result(ShutdownRequest):: the updated instance
    def self.submit(request)
      # RightNet protocols use kind instead of level, so be a little flexible.
      result = instance
      result.level = request[:kind] || request[:level]
      result.immediately! if request[:immediately]
      @@scheduler.schedule_shutdown unless result.continue?
      return result
    end

    # Processes shutdown requests by communicating the need to shutdown an
    # instance with the core agent, if necessary.
    #
    # === Parameters
    # errback(Proc):: error handler or nil
    # audit(Audit):: audit for shutdown action, if needed, or nil.
    #
    # === Block
    # block(Proc):: continuation block for successful handling of shutdown or nil
    #
    # === Return
    # always true
    def process(errback = nil, audit = nil, &block)
      # yield if not shutting down (continuing) or if already requested shutdown.
      if continue? || @shutdown_scheduled
        block.call if block
        return true
      end

      # ensure we have an audit, creating a temporary audit if necessary.
      sender = Sender.instance
      agent_identity = sender.identity
      if audit
        case @level
        when REBOOT, STOP, TERMINATE
          operation = "/forwarder/shutdown"
          payload = {:agent_identity => agent_identity, :kind => @level}
        else
          raise InvalidLevel.new("Unexpected shutdown level: #{@level.inspect}")
        end

        # Request shutdown (kind indicated by operation and/or payload)
        # Use next_tick to ensure that all HTTP i/o is done on main EM reactor thread
        EM_S.next_tick do
          begin
            audit.append_info("Shutdown requested: #{self}")
            sender.send_request(operation, payload) do |r|
              res = OperationResult.from_results(r)
              if res.success?
                @shutdown_scheduled = true
                block.call if block
              else
                fail(errback, audit, "Failed to shutdown instance", res)
              end
            end
          rescue Exception => e
            Log.error("Failed shutting down", e, :trace)
          end
        end
      else
        AuditProxy.create(agent_identity, "Shutdown requested: #{self}") do |new_audit|
          process(errback, new_audit, &block)
        end
      end
      true
    rescue Exception => e
      fail(errback, audit, e)
    end

    protected

    def initialize
      super
      @shutdown_scheduled = false
    end

    # Handles any shutdown failure.
    #
    # === Parameters
    # audit(Audit):: Audit or nil
    # errback(Proc):: error handler or nil
    # msg(String):: Error message that will be audited and logged
    # res(RightScale::OperationResult):: Operation result with additional information
    #
    # === Return
    # always true
    def fail(errback, audit, msg, res = nil)
      if msg.kind_of?(Exception)
        e = msg
        detailed = Log.format("Could not process shutdown state #{self}", e, :trace)
        msg = e.message
      else
        detailed = nil
      end
      msg += ": #{res.content}" if res && res.content
      audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if audit
      Log.error(detailed) if detailed
      errback.call if errback
      true
    end

  end  # ShutdownRequest

end  # RightScale
