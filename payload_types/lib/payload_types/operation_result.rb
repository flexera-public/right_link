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
    
    SUCCESS = 0
    ERROR = 1
    CONTINUE = 2
    RETRY = 3
    TIMEOUT = 4
    MULTICAST = 5
    UNDELIVERED = 5

    # (Integer) Status code
    attr_accessor :status_code
    
    # (String) Message if any
    attr_accessor :content
    
    def initialize(*args)
      @status_code = args[0]
      @content     = args[1] if args.size > 1
    end

    # User friendly error code, does not include content
    #
    # === Return
    # s(String):: Name of result code
    def to_s
      s = case @status_code
        when SUCCESS     then 'success'
        when ERROR       then 'error'
        when CONTINUE    then 'continue'
        when RETRY       then 'retry'
        when TIMEOUT     then 'timeout'
        when MULTICAST   then 'multicast'
        when UNDELIVERED then 'undelivered'
      end
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
    # message(String):: Error message
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.error(message)
      OperationResult.new(ERROR, message)
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

    # Create new timeout status
    #
    # === Parameters
    # content(Object):: Any data associated with timeout - defaults to nil
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.timeout(content = nil)
      OperationResult.new(TIMEOUT, content)
    end

    # Create new multicast status
    #
    # === Parameters
    # targets(Array):: Identity of targets to which request was published
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.multicast(targets)
      OperationResult.new(MULTICAST, targets)
    end

    # Create new undelivered status
    #
    # === Parameters
    # targets(String):: Identity of target to which request could not be delivered
    #
    # === Return
    # (OperationResult):: Corresponding result
    def self.undelivered(target)
      OperationResult.new(MULTICAST, target)
    end

    # Was last operation successful?
    #
    # === Return
    # true:: If status is SUCCESS or CONTINUE
    # false:: Otherwise
    def success?
      status_code == SUCCESS || status_code == CONTINUE || status_code == MULTICAST
    end

    # Was last operation status ERROR?
    #
    # === Return
    # true:: If status is ERROR
    # false:: Otherwise
    def error?
      status_code == ERROR
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

    # Was last operation status TIMEOUT?
    #
    # === Return
    # true:: If status is TIMEOUT
    # false:: Otherwise
    def timeout?
      status_code == TIMEOUT
    end

    # Was last operation status MULTICAST?
    #
    # === Return
    # true:: If status is MULTICAST
    # false:: Otherwise
    def multicast?
      status_code == MULTICAST
    end

    # Was last operation status UNDELIVERED?
    #
    # === Return
    # true:: If status is UNDELIVERED
    # false:: Otherwise
    def undelivered?
      status_code == UNDELIVERED
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [@status_code, @content]
    end

  end
    
end
