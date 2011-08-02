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

require 'socket'
require 'right_agent/actors/agent_manager'

# Extend generic agent manager for fault handling
AgentManager.class_eval do

  include RightScale::Actor
  include RightScale::OperationResultHelper

  on_exception { |_, _, _| }

  expose :record_fault, :reenroll

  # Process fault (i.e. mapper failed to decrypt one of our packets)
  # Vote for re-enrollment
  #
  # === Return
  # (RightScale::OperationResult):: Always returns success
  def record_fault(_)
    RightScale::ReenrollManager.vote
    success_result
  end

  # Force agent to reenroll now
  #
  # === Return
  # (RightScale::OperationResult):: Always returns success
  def reenroll(_)
    RightScale::ReenrollManager.reenroll
    success_result
  end

  # Process exception raised by handling of packet
  # If it's a serialization error and the packet has a valid signature, vote for re-enroll
  #
  # === Parameters
  # e(Exception):: Exception to be analyzed
  # msg(String):: Serialized message that triggered error
  #
  # === Return
  # true:: Always return true
  def self.process_exception(e, msg)
    if e.is_a?(RightScale::Serializer::SerializationError)
      begin
        serializer = RightScale::Serializer.new
        data = serializer.load(msg)
        sig = RightScale::Signature.from_data(data['signature'])
        @cert ||= RightScale::Certificate.load(RightScale::AgentConfig.certs_file('mapper.cert'))
        RightScale::ReenrollManager.vote if sig.match?(@cert)
      rescue Exception => _
        RightScale::Log.error("Failed processing serialization error", e)
      end
    end
    true
  end

  # Process request to restart agent by voting to reenroll
  #
  # === Return
  # true:: Always return true
  def self.process_restart
    RightScale::ReenrollManager.vote
    true
  end

end
