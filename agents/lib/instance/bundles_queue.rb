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

  class BundlesQueue 

    FINAL_BUNDLE = 'end'
    SHUTDOWN_BUNDLE = 'shutdown'

    # Set continuation block to be called after 'close' is called
    #
    # === Parameters
    # shutdown_manager(Object):: shutdown manager to handle shutdown requests.
    #
    # === Block
    # continuation block
    def initialize(shutdown_manager, &continuation)
      @shutdown_manager = shutdown_manager
      @queue = Queue.new
      @continuation = continuation
      @active = false
      @shutdown_scheduled = false
    end

    # Activate queue for execution, idempotent
    # Any pending bundle will be run sequentially in order
    #
    # === Return
    # true:: Always return true
    def activate
      return if @active
      EM.defer { run }
      @active = true
    end

    # Push new context to bundle queue and run next bundle
    #
    # === Return
    # true:: Always return true
    def push(context)
      @queue << context
      true
    end

    # Run next bundle in the queue if active
    # If bundle is FINAL_BUNDLE then call continuation block and deactivate
    #
    # === Return
    # true:: Always return true
    def run
      context = @queue.shift
      if context == FINAL_BUNDLE
        EM.next_tick { @continuation.call if @continuation }
        @active = false
      elsif context == SHUTDOWN_BUNDLE
        unless @shutdown_scheduled
          RightScale::AuditProxy.create(@agent_identity, "Requesting shutdown: #{@shutdown_manager.shutdown_request.level}") do |audit|
            @shutdown_manager.manage_shutdown_request(audit) do
              @shutdown_scheduled = true
            end
          end
        end
        # continue in queue expecting the decommission bundle to finish us off.
        EM.defer { run }
      elsif false == context.decommission && @shutdown_manager.shutdown_request.immediately?
        # immediate shutdown pre-empts any futher attempts to run operational
        # scripts but still allows the decommission bundle to run.
        # proceed ignoring bundles until final or shutdown are encountered.
        context.audit.update_status("Skipped bundle due to immediate shutdown: #{context.payload}")
        EM.defer { run }
      else
        sequence = RightScale::ExecutableSequenceProxy.new(context)
        sequence.callback { audit_status(context) }
        sequence.errback  { audit_status(context) }
        sequence.run
      end
      true
    end

    # Clear queue content
    #
    # === Return
    # true:: Always return true
    def clear
      @queue.clear
      true
    end

    # Close queue so that further call to 'push' will be ignored
    #
    # === Return
    # true:: Always return true
    def close
      push(FINAL_BUNDLE)
    end

    # Audit executable sequence status after it ran
    #
    # === Parameters
    # context(RightScale::OperationContext):: Context used by execution
    #
    # === Return
    # true:: Always return true
    def audit_status(context)
      title = context.decommission ? 'decommission ' : ''
      title += context.succeeded ? 'completed' : 'failed'
      context.audit.update_status("#{title}: #{context.payload}")
      EM.defer { run }
      true
    end

  end

end
