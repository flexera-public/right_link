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

  # Manage receipt of results for a multicast request
  class MulticastReceiver

    # Default number of seconds to wait for all results to be received
    TIMEOUT = 30

    # Create multicast receiver
    #
    # === Parameters
    # description(String):: Description of task; used in info and error messages such as
    #   "Failed to #{description} on ..."
    # done_blk(Proc):: Optional block to be executed after all results have been received; parameters are:
    #   token(String):: Request token
    #   to(Array):: Identity of targets for request, but beware that some may be shared queue names
    #     unlike the "from" list
    #   from(Array):: Identity of responders to request
    #   timed_out(Boolean):: Whether timed out before receiving all results
    # each_blk(Proc):: Optional block to be executed after each result is received; parameters are:
    #   token(String):: Request token
    #   from(String):: Identity of responder
    #   content(Any):: Content of OperationResult sent by target
    # timeout(Integer|nil):: Number of seconds to wait for all results to be received, or nil meaning
    #   wait indefinitely; defaults to TIMEOUT
    def initialize(description, done_blk = nil, each_blk = nil, timeout = TIMEOUT)
      @description = description
      @each = each_blk
      @done = done_blk
      @timeout = timeout
      @timer = nil
      @token = nil
      @to = []
      @from = []
    end

    # Handle multicast result including timing out if not all results received
    # Expected multicast Result sequence is a Result packet containing a MULTICAST OperationResult
    # with list of targets each expected to deliver a Result, followed by those Result packets
    # If the sequence does not begin with a MULTICAST OperationResult, treat it like a
    # multicast with only one target and complete the receipt after the first Result is received
    #
    # === Parameters
    # result(Result):: Result packet to be processed
    #
    # === Return
    # true:: Always return true
    def handle(result)
      begin
        @token = result.token
        r = RightScale::OperationResult.from_results(result)
        if r.multicast?
          @to = r.content
          if @to.size > 0
            @timer = EM::Timer.new(@timeout, lambda { @done.call(@token, @to, @from, true) }) if @timeout
          else
            RightLinkLog.info("No targets found to #{@description}")
          end
        else
          @to = [result.from] if @to.empty?
          @from << result.from
          if r.success?
            @each.call(@token, result.from, r.content) if @each
          else
            msg = "Failed to #{@description} on target #{result.from}"
            msg += ": #{r.content}" if r.content
            RightScale::RightLinkLog.error(msg)
          end
        end
      rescue Exception => e
        RightLinkLog.error("Failed to handle #{@description} for one target: #{e}")
      end

      if @from.size >= @to.size
        begin
          @timer.cancel if @timer
          @done.call(@token, @to, @from, false)
        rescue Exception => e
          RightLinkLog.error("Failed to complete #{@description}: #{e}")
        end
      end
      true
    end

  end # MulticastReceiver

end # RightScale
