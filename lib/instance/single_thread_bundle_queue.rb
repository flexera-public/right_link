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

  class SingleThreadBundleQueue < BundleQueue

    attr_reader :thread_name

    # Set continuation block to be called after 'close' is called
    #
    # === Block
    # continuation block
    def initialize(thread_name = ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME, &continuation)
      super(&continuation)
      @active = false
      @thread = nil
      @thread_name = thread_name
      @pid = nil
      @mutex = Mutex.new
      @queue = Queue.new
      @sequence_finished = ConditionVariable.new
    end

    # Determines if queue is active
    #
    # === Return
    # active(Boolean):: true if queue is active
    def active?
      active = false
      @mutex.synchronize { active = @active }
      return active
    end

    # Activate queue for execution, idempotent
    # Any pending bundle will be run sequentially in order
    #
    # === Return
    # true:: Always return true
    def activate
      @mutex.synchronize do
        unless @active
          @thread = Thread.new { run }
          @active = true
        end
      end
      true
    end

    # Push new context to bundle queue and run next bundle
    #
    # === Return
    # true:: Always return true
    def push(context)
      @queue << context
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

    protected

    # Run next bundle in the queue if active
    # If bundle is FINAL_BUNDLE then call continuation block and deactivate
    #
    # === Return
    # true:: Always return true
    def run
      loop do
        context = @queue.shift
        if context == FINAL_BUNDLE
          break
        elsif context == SHUTDOWN_BUNDLE
          # process shutdown request.
          ShutdownRequest.instance.process
          # continue in queue in the expectation that the decommission bundle will
          # shutdown the instance and its agent normally.
        elsif false == context.decommission && ShutdownRequest.instance.immediately?
          # immediate shutdown pre-empts any futher attempts to run operational
          # scripts but still allows the decommission bundle to run.
          context.audit.update_status("Skipped bundle due to immediate shutdown of #{@thread_name} thread: #{context.payload}")
          # proceed ignoring bundles until final or shutdown are encountered.
        else
          sequence = create_sequence(context)
          sequence.callback { audit_status(sequence) }
          sequence.errback  { audit_status(sequence) }

          # wait until sequence is finished using a ruby mutex conditional.
          # need to synchronize before run to ensure we are waiting before any
          # immediate signalling occurs (under test conditions, etc.).
          @mutex.synchronize do
            sequence.run
            @sequence_finished.wait(@mutex)
            @pid = nil
          end
        end
      end
      true
    rescue Exception => e
      Log.error(Log.format("SingleThreadBundleQueue.run failed for #{@thread_name} thread", e, :trace))
    ensure
      # invoke continuation (off of this thread which is going away).
      @mutex.synchronize { @active = false }
      run_continuation
      @thread = nil
    end

    # Factory method for a new sequence.
    #
    # context(RightScale::OperationContext)
    def create_sequence(context)
      pid_callback = lambda do |sequence|
        # TODO preserve cook PIDs per thread in InstanceState and recover
        # orphaned cook in case of agent crash.
        @mutex.synchronize { @pid = sequence.pid }
      end
      return RightScale::ExecutableSequenceProxy.new(context, :pid_callback => pid_callback )
    end

    # Audit executable sequence status after it ran
    #
    # === Parameters
    # sequence(RightScale::ExecutableSequence):: finished sequence being audited
    #
    # === Return
    # true:: Always return true
    def audit_status(sequence)
      context = sequence.context
      title = context.decommission ? 'decommission ' : ''
      title += context.succeeded ? 'completed' : 'failed'
      context.audit.update_status("#{title}: #{context.payload}")
      true
    rescue Exception => e
      Log.error(Log.format("SingleThreadBundleQueue.audit_status failed for #{@thread_name} thread", e, :trace))
    ensure
      # release queue thread to wait on next bundle in queue. we must ensure
      # that we are not currently on the queue thread so next-tick the signal.
      EM.next_tick { @mutex.synchronize { @sequence_finished.signal } }
    end

  end

end
