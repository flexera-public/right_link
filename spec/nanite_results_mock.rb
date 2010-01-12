# Mock for nanite request results
module RightScale

  class NaniteResultsMock

    def initialize
      @agent_id = RightScale::AgentIdentity.generate
    end

    # Build a valid nanite request results with given content
    def success_results(content = nil, reply_to = '*test*1')
      RightScale::ResultPacket.new(RightScale::AgentIdentity.generate, reply_to,
        { @agent_id => OperationResult.success(content) }, @agent_id)
    end

    def error_results(content, reply_to = '*test*1')
      RightScale::ResultPacket.new(RightScale::AgentIdentity.generate, reply_to,
        { @agent_id => OperationResult.error(content) }, @agent_id)
    end
  end
end