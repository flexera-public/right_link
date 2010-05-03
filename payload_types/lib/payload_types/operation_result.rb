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
  
  # Success status
  class OperationResult

    include Serializable
    
    SUCCESS = 0
    ERROR = 1
    CONTINUE = 2
    RETRY = 3
    TIMEOUT = 4
    
    # (Integer) Status code
    attr_accessor :status_code
    
    # (String) Message if any
    attr_accessor :content
    
    def initialize(*args)
      @status_code = args[0]
      @content     = args[1] if args.size > 1
    end

    # Instantiate from request results
    #
    # === Parameters
    # results(Result):: Nanite Result OR a Hash taken from a Result's "results" field
    #
    # === Return
    # result(RightScale::OperationResult):: Converted operation result
    def self.from_results(results)
      r = results.kind_of?(Hash) ? results : results.results
      
      if r && r.values.size > 0
        value = r.values[0]
        if value.respond_to?(:status_code) && value.respond_to?(:content)
          new(value.status_code, value.content)
        else
          error("Invalid operation result content: #{value.inspect}")
        end
      else
        error("Invalid operation result type: #{results.inspect}")
      end
    end
    
    # Create new success status
    #
    # === Parameters
    # content(Object):: Any data associated with successful results - defaults to nil
    #
    # === Results
    # result(OperationResult):: Corresponding result
    def self.success(content=nil)
      OperationResult.new(SUCCESS, content)
    end

    # Create new error status
    #
    # === Parameters
    # message(String):: Error message
    #
    # === Results
    # result(OperationResult):: Corresponding result
    def self.error(message)
      OperationResult.new(ERROR, message)
    end
    
    # Create new continue status
    #
    # === Parameters
    # content(Object):: Any data associated with continue - defaults to nil
    #
    # === Results
    # result(OperationResult):: Corresponding result
    def self.continue(content=nil)
      OperationResult.new(CONTINUE, content)
    end

    # Create new retry status
    #
    # === Parameters
    # content(Object):: Any data associated with retry - defaults to nil
    #
    # === Results
    # result(OperationResult):: Corresponding result
    def self.retry(content=nil)
      OperationResult.new(RETRY, content)
    end

    # Create new timeout status
    #
    # === Parameters
    # content(Object):: Any data associated with timeout - defaults to nil
    #
    # === Results
    # result(OperationResult):: Corresponding result
    def self.timeout(content=nil)
      OperationResult.new(TIMEOUT, content)
    end

    # Was last operation successful?
    #
    # === Results
    # true:: If status is SUCCESS or CONTINUE
    # false:: Otherwise
    def success?
      status_code == SUCCESS || status_code == CONTINUE
    end
    
    # Was last operation status CONTINUE?
    #
    # === Results
    # true:: If status is CONTINUE
    # false:: Otherwise
    def continue?
      status_code == CONTINUE
    end

    # Was last operation status RETRY?
    #
    # === Results
    # true:: If status is RETRY
    # false:: Otherwise
    def retry?
      status_code == RETRY
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @status_code, @content ]
    end

  end
    
end
