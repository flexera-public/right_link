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

# Mock for nanite request results
module RightScale

  class NaniteResultsMock

    def initialize
      @agent_id = RightScale::AgentIdentity.generate
    end

    # Build a valid nanite request results with given content
    def success_results(content = nil, reply_to = '*test*1')
      RightScale::Result.new(RightScale::AgentIdentity.generate, reply_to,
        { @agent_id => OperationResult.success(content) }, @agent_id)
    end

    def error_results(content, reply_to = '*test*1')
      RightScale::Result.new(RightScale::AgentIdentity.generate, reply_to,
        { @agent_id => OperationResult.error(content) }, @agent_id)
    end

  end
  
end
