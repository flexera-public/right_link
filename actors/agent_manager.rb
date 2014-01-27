#
# Copyright (c) 2009-2014 RightScale Inc
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

  expose :record_fault, :restart, :reenroll

  # Process fault (i.e. router failed to decrypt one of our packets)
  # Vote for re-enrollment
  #
  # === Return
  # (RightScale::OperationResult):: Always returns success
  def record_fault(_)
    RightScale::ReenrollManager.vote
    success_result
  end

  # Force agent to restart now
  # Optionally reconfigure agent before doing so
  #
  # === Parameters
  # options(Hash|NilClass):: Agent configuration option changes
  #
  # === Return
  # (RightScale::OperationResult):: Always returns success
  def restart(options)
    @agent.update_configuration(options) if options.is_a?(Hash) && options.any?
    @agent.terminate("remote restart")
    success_result
  end

  # Force agent to reenroll now
  # Optionally reconfigure agent before doing so
  #
  # === Parameters
  # options(Hash|NilClass):: Agent configuration option changes
  #
  # === Return
  # (RightScale::OperationResult):: Always returns success
  def reenroll(options)
    @agent.update_configuration(options) if options.is_a?(Hash) && options.any?
    RightScale::ReenrollManager.reenroll!
    success_result
  end

end
