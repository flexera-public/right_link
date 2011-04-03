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
#

module RightScale
  
  # Container for status and result of an operation
  class OperationResult

    include Serializable
    
    # Result status code
    SUCCESS      = 0
    ERROR        = 1
    CONTINUE     = 2
    RETRY        = 3
    NON_DELIVERY = 4
    MULTICAST    = 5 # Deprecated for agents at version 13 or above

    # Non-delivery reasons
    NON_DELIVERY_REASONS = [
      NO_TARGET            = "no target",
      UNKNOWN_TARGET       = "unknown target",
      NO_ROUTE_TO_TARGET   = "no route to target",
      TARGET_NOT_CONNECTED = "target not connected",
      TTL_EXPIRATION       = "TTL expiration",
      RETRY_TIMEOUT        = "retry timeout"
    ]

    # Maximum characters included in display of error
    MAX_ERROR_SIZE = 60

    # (Integer) Status code
    attr_accessor :status_code
    
    # (Object) Result data, if any
    attr_accessor :content
    
    def initialize(*args)
      @status_code = args[0]
      @content     = args[1] if args.size > 1
    end

    # User friendly result
    # Does not include content except in the case of error or non-delivery
    #
    # === Return
    # (String):: Name of result code
    def to_s
      status(reason = true)
    end

    # User friendly result status
    #
    # === Parameters
    # reason(Boolean):: Whether to include failure reason information, default to false
    #
    # === Return
    # (String):: Name of result code
    def status(reason = false)
      case @status_code
      when SUCCESS      then 'success'
      when ERROR        then 'error' + (reason ? " (#{truncated_error})" : "")
      when CONTINUE     then 'continue'
      when RETRY        then 'retry'
      when NON_DELIVERY then 'non-delivery' + (reason ? " (#{@content})" : "")
      when MULTICAST    then 'multicast'
      end
    end

    # Limited length error string
    #
    # === Return
    # e(String):: String of no more than MAX_ERROR_SIZE characters
    def truncated_error
      e = @content.is_a?(String) ? @content : @content.inspect
      e = e[0, MAX_ERROR_SIZE - 3] + "..." if e.size > (MAX_ERROR_SIZE - 3)
      e
    end

    # Instantiate from request results
    # Ignore all but first result if results is a hash
    #
    # === Parameters
    # results(Result|Hash|OperationResult|nil):: Result or the Result "results" field
    #
    # === Return
    # (RightScale::OperationResult):: Converted operation result
    def self.from_results(results)
      r = results.kind_of?(Result) ? results.results : results
      if r && r.respond_to?(:status_code) && r.respond_to?(:content)
        new(r.status_code, r.content)
      elsif r && r.kind_of?(Hash) && r.values.size > 0
        r = r.values[0]
        if r.respond_to?(:status_code) && r.respond_to?(:content)
          new(r.status_code, r.content)
        else
          error("Invalid operation result content: #{r.inspect}")
        end
      elsif r.nil?
        error("No results")
      else
        error("Invalid operation result type: #{results.inspect}")
      end
    end
    
    # Create new success status
    #
    # === Parameters
    # content(Object):: Any data associated with successful results - defaults to nil
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.success(content = nil)
      OperationResult.new(SUCCESS, content)
    end

    # Create new error status
    #
    # === Parameters
    # message(String):: Error description
    # exception(Exception|String):: Associated exception or other parenthetical error information
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.error(message, exception = nil)
      OperationResult.new(ERROR, RightLinkLog.format(message, exception))
    end

    # Create new continue status
    #
    # === Parameters
    # content(Object):: Any data associated with continue - defaults to nil
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.continue(content = nil)
      OperationResult.new(CONTINUE, content)
    end

    # Create new retry status
    #
    # === Parameters
    # content(Object):: Any data associated with retry - defaults to nil
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.retry(content = nil)
      OperationResult.new(RETRY, content)
    end

    # Create new non-delivery status
    #
    # === Parameters
    # reason(String):: Non-delivery reason from NON_DELIVERY_REASONS
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.non_delivery(reason)
      OperationResult.new(NON_DELIVERY, reason)
    end

    # Create new multicast status
    # Deprecated for agents at version 13 or above
    #
    # === Parameters
    # targets(Array):: Identity of targets to which request was published
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.multicast(targets)
      OperationResult.new(MULTICAST, targets)
    end

    # Was last operation successful?
    #
    # === Return
    # true:: If status is SUCCESS or CONTINUE
    # false:: Otherwise
    def success?
      status_code == SUCCESS || status_code == CONTINUE
    end

    # Was last operation unsuccessful?
    #
    # === Return
    # true:: If status is ERROR or NON_DELIVERY
    # false:: Otherwise
    def error?
      status_code == ERROR || status_code == NON_DELIVERY
    end

    # Was last operation status CONTINUE?
    #
    # === Return
    # true:: If status is CONTINUE
    # false:: Otherwise
    def continue?
      status_code == CONTINUE
    end

    # Was last operation status RETRY?
    #
    # === Return
    # true:: If status is RETRY
    # false:: Otherwise
    def retry?
      status_code == RETRY
    end

    # Was last operation status NON_DELIVERY?
    #
    # === Return
    # true:: If status is NON_DELIVERY
    # false:: Otherwise
    def non_delivery?
      status_code == NON_DELIVERY
    end

    # Was last operation status MULTICAST?
    # Deprecated for agents at version 13 or above
    #
    # === Return
    # true:: If status is MULTICAST
    # false:: Otherwise
    def multicast?
      status_code == MULTICAST
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [@status_code, @content]
    end

  end # OperationResult

  # Helper module to simplify result construction
  module OperationResultHelpers

    def success_result(*args) OperationResult.success(*args) end
    def error_result(*args) OperationResult.error(*args) end
    def continue_result(*args) OperationResult.continue(*args) end
    def retry_result(*args) OperationResult.retry(*args) end
    def non_delivery_result(*args) OperationResult.non_delivery(*args) end
    def result_from(*args) OperationResult.from_results(*args) end

  end # OperationResultHelpers

end # RightScale
