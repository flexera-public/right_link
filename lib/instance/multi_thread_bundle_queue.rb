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

  class MultiThreadBundleQueue < BundleQueue

    THREAD_QUEUE_CLOSED_BUNDLE = 'thread queue closed'

    # Set continuation block to be called after 'close' is called
    #
    # === Block
    # continuation block
    def initialize(&continuation)
      super(&continuation)
      @active = false
      @thread = nil
      @mutex = Mutex.new
      @queue = Queue.new
      @thread_name_to_queue = {}
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
      @mutex.synchronize { @thread_name_to_queue.each_value { |queue| queue.clear } }
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
      close_requested = false
      shutdown_requested = false
      loop do
        context = @queue.shift
        if context == FINAL_BUNDLE
          if close_thread_queues
            close_requested = true
          else
            break
          end
        elsif context == THREAD_QUEUE_CLOSED_BUNDLE
          unless groom_thread_queues
            if shutdown_requested
              # reset shutdown flag, push shutdown and wait for FINAL_BUNDLE
              shutdown_requested = false
              push_to_thread_queue(SHUTDOWN_BUNDLE)
            else
              break
            end
          end
        elsif context == SHUTDOWN_BUNDLE
          if close_thread_queues
            # defer shutdown until all thread queues close (threads are
            # uninterruptable but the user can always kick the plug out).
            shutdown_requested = true
          else
            # push shutdown and wait for FINAL_BUNDLE
            push_to_thread_queue(SHUTDOWN_BUNDLE)
          end
        elsif false == context.decommission && ShutdownRequest.instance.immediately?
          # immediate shutdown pre-empts any futher attempts to run operational
          # scripts but still allows the decommission bundle to run.
          context.audit.update_status("Skipped bundle due to immediate shutdown: #{context.payload}")
          # proceed ignoring bundles until final or shutdown are encountered.
        else
          push_to_thread_queue(context) unless close_requested
        end
      end
      true
    rescue Exception => e
      Log.error(Log.format("MultiThreadBundleQueue.run failed", e, :trace))
    ensure
      # invoke continuation (off of this thread which is going away).
      @mutex.synchronize { @active = false }
      EM.next_tick { @continuation.call } if @continuation
      @thread = nil
    end

    # Pushes a context to a thread based on a name determined from the context.
    #
    # === Parameters
    # context(Object):: any kind of context object
    #
    # === Return
    # true:: always true
    def push_to_thread_queue(context)
      thread_name = context.respond_to?(:thread_name) ? context.thread_name : ::RightScale::ExecutableBundle::DEFAULT_THREAD_NAME
      queue = nil
      @mutex.synchronize do
        queue = @thread_name_to_queue[thread_name]
        unless queue
          # continuation for when thread-named queue is finally closed.
          queue = create_thread_queue(thread_name) { push(THREAD_QUEUE_CLOSED_BUNDLE) }
          @thread_name_to_queue[thread_name] = queue
        end
      end

      # push context to selected thread queue
      queue.push(context)

      # always (re)activate in case an individual thread queue died unexpectedly.
      # has no effect if already active.
      queue.activate
      true
    end

    # Factory method for a thread-specific queue.
    #
    # === Parameters
    # thread_name(String):: name of thread for queue being created
    # continuation(Proc):: continuation run on thread termination
    #
    # === Return
    # queue(BundleQueue):: a new thread-specific queue
    def create_thread_queue(thread_name, &continuation)
      return SingleThreadBundleQueue.new(thread_name, &continuation)
    end

    # Deletes any inactive queues from the hash of known queues.
    #
    # === Return
    # still_active(Boolean):: true if any queues are still active
    def groom_thread_queues
      still_active = false
      @mutex.synchronize do
        @thread_name_to_queue.delete_if { |_, queue| false == queue.active? }
        still_active = false == @thread_name_to_queue.empty?
      end
      return still_active
    end

    # Closes all thread queues.
    #
    # === Return
    # result(Boolean):: true if any queues are still active (and stopping)
    def close_thread_queues
      still_active = false
      @mutex.synchronize do
        @thread_name_to_queue.each_value do |queue|
          if queue.active?
            queue.close
            still_active = true
          end
        end
      end
      return still_active
    end

  end  # MultiThreadBundleQueue

end  # RightScale
