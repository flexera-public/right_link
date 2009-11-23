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

class InstanceSetup

  include Nanite::Actor

  expose :report_state

  # Number of seconds to wait before switching to offline mode
  RECONNECT_GRACE_PERIOD = 30

  # Boot if and only if instance state is 'booting'
  #
  # === Parameters
  # agent_identity<String>:: Serialized agent identity for current agent
  def initialize(agent_identity)
    @boot_retries = 0
    @agent_identity = agent_identity
    RightScale::InstanceState.init(agent_identity)
    EM.threadpool_size = 1
    # Schedule boot sequence, don't run it now so agent is registered first
    EM.next_tick { init_boot } if RightScale::InstanceState.value == 'booting'
  end

  # Retrieve current instance state
  #
  # === Return
  # state<RightScale::OperationResult>:: Success operation result containing instance state
  def report_state
    state = RightScale::OperationResult.success(RightScale::InstanceState.value)
  end

  # Handle deconnection notification from broker
  # Start timer to give the amqp gem some time to retry connecting
  #
  # === Parameters
  # status<Symbol>:: Connection status, one of :connected or :deconnected
  #
  # === Return
  # true:: Always return true
  def connection_status(status)
    if status == :deconnected
      @offline_timer ||= EM::Timer.new(RECONNECT_GRACE_PERIOD) { RightScale::RequestForwarder.enable_offline_mode }
    else
      # Cancel offline timer if there was one
      if @offline_timer
        @offline_timer.cancel
        @offline_timer = nil
      end
      RightScale::RequestForwarder.disable_offline_mode
    end
    true
  end

  protected

  # We start off by setting the instance 'r_s_version' in the core site and
  # then proceed with the actual boot sequence
  #
  # === Return
  # true:: Always return true
  def init_boot
    request("/booter/set_r_s_version", { :agent_identity => @agent_identity, :r_s_version => 6 }) do |r|
      res = RightScale::OperationResult.from_results(r)
      strand("Failed to set_r_s_version", res) unless res.success?
      enable_managed_login
    end
    true
  end

  # Enable managed SSH for this instance, then continue with boot. Ensures that
  # managed SSH users can login to troubleshoot stranded and other 'interesting' events
  #
  # === Return
  # true:: Always return true
  def enable_managed_login
    request('/booter/get_login_policy', {:agent_identity => @agent_identity}) do |r|
      res = RightScale::OperationResult.from_results(r)

      if res.success?
        policy  = res.content
        auditor = RightScale::AuditorProxy.new(policy.audit_id)
        begin
          RightScale::LoginManager.instance.update_policy(policy)
          auditor.create_new_section('Managed login enabled')
          audit = "Authorized users:\n"
          policy.users.each do |u|
            audit += "    #{u.uuid} #{u.common_name.ljust(40)}\n"
          end
          auditor.append_info(audit)
        rescue Exception => e
          auditor.create_new_section('Failed to enable managed login')
          auditor.append_error("#{e.class.name}: #{e.message}")
          auditor.append_error(e.backtrace.join("\n"))
        end
      else
        RightScale::RightLinkLog.error("Could not get login policy: #{res.content}")
      end

      boot
    end
  end

  # Retrieve software repositories and configure mirrors accordingly then proceed to
  # retrieving and running boot bundle.
  #
  # === Return
  # true:: Always return true
  def boot
    request("/booter/get_repositories", @agent_identity) do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        reps = res.content.repositories
        @auditor = RightScale::AuditorProxy.new(res.content.audit_id)
        audit = "Using the following software repositories:\n"
        reps.each { |rep| audit += "  - #{rep.to_s}\n" }
        @auditor.create_new_section("Software repositories configured")
        @auditor.append_info(audit)
        configure_repositories(reps)
        run_boot_bundle do |result|
          if result.success?
            RightScale::InstanceState.value = 'operational'
          else
            strand("Failed to run boot scripts", result)
          end
        end
      else
        strand("Failed to retrieve software repositories", res)
      end
    end
    true
  end

  # Log error to local log file and set instance state to stranded
  #
  # === Parameters
  # msg<String>:: Error message that will be audited and logged
  # res<RightScale::OperationResult>:: Operation result with additional information
  #
  # === Return
  # true:: Always return true
  def strand(msg, res)
    RightScale::InstanceState.value = 'stranded'
    msg += ": #{res.content}" if res.content
    @auditor.append_error(msg) if @auditor
    true
  end

  # Configure software repositories
  # Note: the configurators may return errors when the platform is not what they expect,
  # for now log error and keep going (to replicate legacy behavior).
  #
  # === Parameters
  # repositories<Array[<RepositoryInstantiation>]>:: repositories to be configured
  #
  # === Return
  # true:: Always return true
  def configure_repositories(repositories)
    repositories.each do |repo|
      begin
        klass = repo.name.to_const
        unless klass.nil?
          fz = nil
          if repo.frozen_date
            # gives us date for yesterday since the mirror for today may not have been generated yet
            fz = (Date.parse(repo.frozen_date) - 1).to_s
            fz.gsub!(/-/,"")
          end
          klass.generate("none", repo.base_urls, fz)
        end
      rescue Exception => e
        RightScale::RightLinkLog.error(e.message)
      end
    end
    if system('which apt-get')
      ENV['DEBIAN_FRONTEND'] = 'noninteractive' # this prevents prompts
      @auditor.append_output(`apt-get update 2>&1`)
    end
    true
  end

  # Retrieve and run boot scripts
  #
  # === Return
  # true:: Always return true
  def run_boot_bundle
    options = { :agent_identity => @agent_identity, :audit_id => @auditor.audit_id }
    request("/booter/get_boot_bundle", options) do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        bundle = res.content
        sequence = RightScale::ExecutableSequence.new(bundle, @agent_identity)
        sequence.callback do
          EM.next_tick do
            @auditor.update_status("completed: #{bundle}")
            yield RightScale::OperationResult.success
          end
        end
        sequence.errback  { EM.next_tick { yield RightScale::OperationResult.error("Failed to run boot bundle") } }

        # We want to be able to use Chef providers which use EM (e.g. so they can use RightScale::popen3), this means
        # that we need to synchronize the chef thread with the EM thread since providers run synchronously. So create
        # a thread here and run the sequence in it. Use EM.next_tick to switch back to EM's thread.
        EM.defer { sequence.run }
    
      else
        msg = "Failed to retrieve boot scripts"
        msg += ": #{res.content}" if res.content
        yield RightScale::OperationResult.error(msg)
      end
    end
    true
  end

end
