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

class InstanceScheduler

  include Nanite::Actor

  expose :schedule_bundle, :execute

  # Setup signal traps for running decommission scripts
  # Start worker thread for processing executable bundles
  #
  # === Parameters
  # agent<Nanite::Agent>:: Host agent
  def initialize(agent)
    @scheduled_bundles = Queue.new
    @decommissioning = false
    @agent_identity = agent.identity
    RightScale::AgentTagsManager.new(agent)
    @sig_handler = Signal.trap('USR1') { decommission_on_exit } unless RightScale::RightLinkConfig[:platform].windows?
    @worker_thread = Thread.new { run_bundles }
  end

  # Schedule given script bundle so it's run as soon as possible
  #
  # === Parameter
  # bundle<RightScale::ExecutableBundle>:: Bundle to be scheduled
  #
  # === Return
  # res<RightScale::OperationResult>:: Always returns success
  def schedule_bundle(bundle)
    auditor = RightScale::AuditorProxy.new(bundle.audit_id)
    auditor.update_status("Scheduling execution of #{bundle.to_s}")
    @scheduled_bundles.push(bundle)
    res = RightScale::OperationResult.success
  end

  # Ask agent to execute given recipe
  # Agent must forward request to core agent which will in turn run
  # schedule_bundle on this agent
  #
  # === Parameters
  # options[:recipe]<String>:: Recipe name
  # options[:json]<Hash>:: Serialized hash of attributes to be used when running recipe
  #
  # === Return
  # true:: Always return true
  def execute(options)
    options[:agent_identity] = RightScale::AgentIdentity.serialized_from_nanite(@agent_identity)
    request('/forwarder/schedule_recipe', options) do |r|
      res = RightScale::OperationResult.from_results(r)
      unless res.success?
        RightScale::RightLinkLog.info("Failed to execute recipe: #{res.content}")
      end
    end
    true
  end

  # Schedule decommission, returns an error if instance is already decommissioning
  #
  # === Parameter
  # bundle<RightScale::ExecutableBundle>:: Decommission bundle
  #
  # === Return
  # res<RightScale::OperationResult>:: Status value, either success or error with message
  def schedule_decommission(bundle)
    return res = RightScale::OperationResult.error('Instance is already decommissioning') if @decommissioning
    @scheduled_bundles.clear # Cancel any pending bundle
    RightScale::InstanceState.value = 'decommissioning'
    @decommissioning = true
    schedule_bundle(bundle)
    res = RightScale::OperationResult.success
  end

  protected

  # Worker thread loop which runs bundles pushed to the scheduled bundles queue
  # Push the string 'end' to the queue to end the thread
  #
  # === Return
  # true:: Always return true
  def run_bundles
    bundle = @scheduled_bundles.shift
    if bundle != 'end'
      sequence = RightScale::ExecutableSequence.new(bundle)
      sequence.callback do
        @auditor.update_status("completed: #{bundle}")
        run_bundles
      end
      sequence.errback { run_bundles }
      sequence.run
    end
    RightScale::InstanceState.value = 'decommissioned' if @decommissioning
    EM.next_tick { terminate }
    true
  end

  # Run decommission scripts, stop worker thread, join and exit
  #
  # === Return
  # true:: Always return true
  def decommission_on_exit
    request('/booter/get_decommission_bundle', :agent_identity => @agent_identity) do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        schedule_decommission(res.content)
      else
        RightScale::RightLinkLog.debug("Failed to retrieve decommission bundle: #{res.content}")
      end
      @scheduled_bundles.push('end')
    end
    true
  end

  # Call previously registered signal handler if any or exit
  #
  # === Return
  # Well... does not return...
  def terminate
    RightScale::RightLinkLog.info("Instance agent #{@agent_identity} terminating")
    RightScale::CommandRunner.stop
    @sig_handler.call if @sig_handler && @sig_handler.respond_to?(:call)
    Process.kill('TERM', Process.pid) unless @sig_handler && @sig_handler != "DEFAULT"
  end

end
