#
# Copyright (c) 2009-2011 RightScale Inc
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

  # Abstract base class for a Bundle Queue.
  class BundleQueue

    FINAL_BUNDLE = 'end'
    SHUTDOWN_BUNDLE = 'shutdown'

    # Set continuation block to be called after 'close' is called
    #
    # === Block
    # continuation block
    def initialize(&continuation)
      @continuation = continuation
    end

    # Determines if queue is active
    #
    # === Return
    # active(Boolean):: true if queue is active
    def active?
      raise NotImplementedError.new("must be overridden")
    end

    # Activate queue for execution, idempotent
    # Any pending bundle will be run sequentially in order
    #
    # === Return
    # true:: Always return true
    def activate
      raise NotImplementedError.new("must be overridden")
    end

    # Determines if queue is busy
    #
    # === Return
    # active(Boolean):: true if queue is busy
    def busy?
      raise NotImplementedError.new("must be overridden")
    end

    # Push new context to bundle queue and run next bundle
    #
    # === Parameters
    # context(Object):: any supported kind of context
    #
    # === Return
    # true:: Always return true
    def push(context)
      raise NotImplementedError.new("must be overridden")
    end

    # Clear queue content
    #
    # === Return
    # true:: Always return true
    def clear
      raise NotImplementedError.new("must be overridden")
    end

    # Close queue so that further call to 'push' will be ignored
    #
    # === Return
    # true:: Always return true
    def close
      raise NotImplementedError.new("must be overridden")
    end

    protected

    # Invokes continuation (off of the current thread which may be going away).
    #
    # === Return
    # true:: Always return true
    def run_continuation
      EM.next_tick { @continuation.call } if @continuation
      true
    end

  end

end
