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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'volume_management'))

class InstanceSetup

  include RightScale::Actor
  include RightScale::OperationResultHelper
  include RightScale::VolumeManagementHelper

  expose :report_state

  # Amount of seconds to wait between set_r_s_version calls attempts
  RECONNECT_DELAY = 5

  # Amount of seconds to wait before shutting down if boot hasn't completed
  SUICIDE_DELAY = 45 * 60

  # Time between attempts to get missing inputs.
  MISSING_INPUT_RETRY_DELAY_SECS = 20

  # Maximum time between nag audits for missing inputs.
  MISSING_INPUT_AUDIT_DELAY_SECS = 2 * 60

  # Tag set on instances that are part of an array
  AUTO_LAUNCH_TAG ='rs_launch:type=auto'

  # Boot if and only if instance state is 'booting'
  # Prime timer for shutdown on unsuccessful boot ('suicide' functionality)
  #
  # === Parameters
  # agent_identity(String):: Serialized agent identity for current agent
  def initialize(agent_identity)
    @agent_identity    = agent_identity
    @got_boot_bundle   = false
    EM.threadpool_size = 1
    RightScale::InstanceState.init(@agent_identity)
    RightScale::Log.force_debug if RightScale::CookState.dev_mode_enabled?

    # Schedule boot sequence, don't run it now so agent is registered first
    if RightScale::InstanceState.value == 'booting'
      EM.next_tick { init_boot }
    else
      RightScale::Sender.instance.initialize_offline_queue
      RightScale::Sender.instance.start_offline_queue

      # handle case of a decommission which was abruptly interrupted and never
      # shutdown the instance (likely due to a decommission script which induced
      # an unexpected fault in the agent).
      #
      # note that upon successfuly reboot (or start of a stopped instance) the
      # instance state file is externally reset to a rebooting state (thus
      # avoiding the dreaded infinite reboot/stop scenario).
      if RightScale::InstanceState.value == 'decommissioning' && (kind = RightScale::InstanceState.decommission_type)
        EM.next_tick { recover_decommission(user_id = nil, skip_db_update = false, kind) }
      end
    end

    # Setup suicide timer which will cause instance to shutdown if the rs_launch:type=auto tag
    # is set and the instance has not gotten its boot bundle after SUICIDE_DELAY seconds and this is
    # the first time this instance boots
    if RightScale::InstanceState.initial_boot?
      @suicide_timer = EM::Timer.new(SUICIDE_DELAY) do
        if RightScale::InstanceState.startup_tags.include?(AUTO_LAUNCH_TAG) && !@got_boot_bundle
          msg = "Shutting down after having tried to boot for #{SUICIDE_DELAY / 60} minutes"
          RightScale::Log.error(msg)
          @audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if @audit
          RightScale::Platform.controller.shutdown
        end
      end
    end

  end

  # Retrieve current instance state
  #
  # === Return
  # (RightScale::OperationResult):: Success operation result containing instance state
  def report_state
    success_result(RightScale::InstanceState.value)
  end

  # Handle disconnected notification from broker, enter offline mode
  #
  # === Parameters
  # status(Symbol):: Connection status, one of :connected or :disconnected
  #
  # === Return
  # true:: Always return true
  def connection_status(status)
    if status == :disconnected
      RightScale::Sender.instance.enable_offline_mode
    else
      RightScale::Sender.instance.disable_offline_mode
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
    RightScale::Sender.instance.initialize_offline_queue
    payload = {:agent_identity => @agent_identity,
               :r_s_version    => RightScale::AgentConfig.protocol_version,
               :resource_uid   => RightScale::InstanceState.resource_uid}
    req = RightScale::IdempotentRequest.new('/booter/declare', payload, :retry_on_error => true)
    req.callback do |res|
      RightScale::Sender.instance.start_offline_queue
      enable_managed_login
    end
    req.run
    true
  end

  # Enable managed SSH for this instance, then continue with boot. Ensures that
  # managed SSH users can login to troubleshoot stranded and other 'interesting' events
  #
  # === Return
  # true:: Always return true
  def enable_managed_login
    if !RightScale::LoginManager.instance.supported_by_platform?
      setup_volumes
    else
      req = RightScale::IdempotentRequest.new('/booter/get_login_policy', {:agent_identity => @agent_identity})

      req.callback do |policy|
        audit = RightScale::AuditProxy.new(policy.audit_id)
        begin
          audit_content = RightScale::LoginManager.instance.update_policy(policy)
          if audit_content
            audit.create_new_section('Managed login enabled')
            audit.append_info(audit_content)
          end
        rescue Exception => e
          audit.create_new_section('Failed to enable managed login')
          audit.append_error("Error applying login policy: #{e}", :category => RightScale::EventCategories::CATEGORY_ERROR)
          RightScale::Log.error('Failed to enable managed login', e, :trace)
        end
        boot
      end

      req.errback do |res|
        RightScale::Log.error('Could not get login policy', res)
        boot
      end

      req.run
    end
  end

  # Attach EBS volumes to drive letters on Windows
  #
  # === Return
  # true:: Always return true
  def setup_volumes
    # managing planned volumes is currently only needed in Windows and only if
    # this is not a reboot scenario.
    if RightScale::InstanceState.reboot?
      boot
    else
      RightScale::AuditProxy.create(@agent_identity, 'Planned volume management') do |audit|
        @audit = audit
        manage_planned_volumes do
          @audit = nil
          boot
        end
      end
    end
    true
  end

  # Retrieve software repositories and configure mirrors accordingly then proceed to
  # retrieving and running boot bundle.
  #
  # === Return
  # true:: Always return true
  def boot
    req = RightScale::IdempotentRequest.new('/booter/get_repositories', { :agent_identity => @agent_identity })

    req.callback do |res|
      @audit = RightScale::AuditProxy.new(res.audit_id)
      unless RightScale::Platform.windows? || RightScale::Platform.darwin?
        reps = res.repositories
        audit_content = "Using the following software repositories:\n"
        reps.each { |rep| audit_content += "  - #{rep.to_s}\n" }
        @audit.create_new_section('Configuring software repositories')
        @audit.append_info(audit_content)
        configure_repositories(reps)
        @audit.update_status('Software repositories configured')
      end
      @audit.create_new_section('Preparing boot bundle')
      prepare_boot_bundle do |prep_res|
        if prep_res.success?
          @audit.update_status('Boot bundle ready')
          run_boot_bundle(prep_res.content) do |boot_res|
            if boot_res.success?
              # want to go operational only if no immediate shutdown request.
              # immediate shutdown requires we stay in the current (booting)
              # state pending full reboot/restart of instance so that we don't
              # bounce between operational and booting in a multi-reboot case.
              # if shutdown is deferred, then go operational before shutdown.
              shutdown_request = RightScale::ShutdownRequest.instance
              if shutdown_request.immediately?
                # process the shutdown request immediately since the
                # operational bundles queue will not start in this case.
                errback = lambda { strand("Failed to #{shutdown_request} while running boot sequence") }
                shutdown_request.process(errback, @audit)
              else
                # any deferred shutdown request was submitted to the
                # operational bundles queue and will execute later.
                RightScale::InstanceState.value = 'operational'
              end
            else
              strand('Failed to run boot sequence', boot_res)
            end
          end
        else
          strand('Failed to prepare boot bundle', prep_res)
        end
      end
    end

    req.errback do|res|
      strand('Failed to retrieve software repositories', res)
    end

    req.run
    true
  end

  # Log error to local log file and set instance state to stranded
  #
  # === Parameters
  # msg(String):: Error message that will be audited and logged
  # res(RightScale::OperationResult):: Operation result with additional information
  #
  # === Return
  # true:: Always return true
  def strand(msg, res = nil)
    # attempt to provide details of exception or result which caused stranding.
    detailed = nil
    if msg.kind_of? Exception
      e = msg
      detailed = RightScale::Log.format("Instance stranded", e, :trace)
      msg = e.message
    end
    res = res.content if res.respond_to?(:content)
    msg += ": #{res}" if res

    @audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if @audit
    RightScale::Log.error(detailed) if detailed

    # set stranded state last in case this would prevent final audits from being
    # sent (as it does in testing).
    RightScale::InstanceState.value = 'stranded'
    true
  end

  # Overrides default shutdown management failure handler in order to strand.
  def handle_failed_shutdown_request(audit, msg, res = nil)
    @audit = audit
    strand(msg, res)
  end

  # Configure software repositories
  # Note: the configurators may return errors when the platform is not what they expect,
  # for now log error and keep going (to replicate legacy behavior).
  #
  # === Parameters
  # repositories(Array[(RepositoryInstantiation)]):: repositories to be configured
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
        RightScale::Log.error("Failed to configure repositories", e)
      end
    end
    if system('which apt-get')
      ENV['DEBIAN_FRONTEND'] = 'noninteractive' # this prevents prompts
      @audit.append_output(`apt-get update 2>&1`)
    elsif system('which yum')
      @audit.append_output(`yum clean metadata`)
    end
    true
  end

  # Retrieve missing inputs if any
  #
  # === Block
  # Calls given block passing in one argument of type RightScale::OperationResult
  # The argument contains either a failure with associated message or success
  # with the corresponding boot bundle.
  #
  # === Return
  # true:: Always return true
  def prepare_boot_bundle(&cb)
    RightScale::AgentTagsManager.instance.tags do |tags|
      RightScale::InstanceState.startup_tags = tags
      if tags.empty?
        @audit.append_info('No tags discovered on startup')
      else
        @audit.append_info("Tags discovered on startup: '#{tags.join("', '")}'")
      end
      payload = {:agent_identity => @agent_identity, :audit_id => @audit.audit_id}
      req = RightScale::IdempotentRequest.new('/booter/get_boot_bundle', payload)

      req.callback do |bundle|
        if bundle.executables.any? { |e| !e.ready }
          retrieve_missing_inputs(bundle) { cb.call(success_result(bundle)) }
        else
          yield success_result(bundle)
        end
      end

      req.errback do |res|
        yield error_result(RightScale::Log.format('Failed to retrieve boot scripts', res))
      end

      req.run
    end
  end

  # Retrieve missing inputs for recipes and RightScripts stored in
  # @recipes and @scripts respectively, update recipe attributes, RightScript
  # parameters and ready fields (set ready field to true if attempt was successful,
  # false otherwise).
  # This is for environment variables that we are waiting on.
  # Retries forever.
  #
  # === Parameters
  # bundle(ExecutableBundle):: bundle containing at least one script/recipe with missing inputs.
  # last_missing_inputs(Hash):: state of missing inputs for refreshing audit message as needed or nil.
  #
  # === Block
  # Continuation block, will be called once attempt to retrieve attributes is completed
  #
  # === Return
  # true:: Always return true
  def retrieve_missing_inputs(bundle, last_missing_inputs = nil, &cb)
    scripts = bundle.executables.select { |e| e.is_a?(RightScale::RightScriptInstantiation) }
    recipes = bundle.executables.select { |e| e.is_a?(RightScale::RecipeInstantiation) }
    scripts_ids = scripts.select { |s| !s.ready }.map { |s| s.id }
    recipes_ids = recipes.select { |r| !r.ready }.map { |r| r.id }
    payload = {:agent_identity => @agent_identity,
               :scripts_ids    => scripts_ids,
               :recipes_ids    => recipes_ids}
    req = RightScale::IdempotentRequest.new('/booter/get_missing_attributes', payload)

    req.callback do |res|
      res.each do |e|
        if e.is_a?(RightScale::RightScriptInstantiation)
          if script = scripts.detect { |s| s.id == e.id }
            script.ready = true
            script.parameters = e.parameters
          end
        else
          if recipe = recipes.detect { |s| s.id == e.id }
            recipe.ready = true
            recipe.attributes = e.attributes
          end
        end
      end
      pending_executables = bundle.executables.select { |e| !e.ready }
      if pending_executables.empty?
        yield
      else
        # keep state to provide fewer but more meaningful audits.
        last_missing_inputs ||= {}
        last_missing_inputs[:executables] ||= {}

        # don't need to audit on each attempt to resolve missing inputs, but nag
        # every so often to let the user know this server is still waiting.
        last_audit_time = last_missing_inputs[:last_audit_time]
        audit_missing_inputs = last_audit_time.nil? || (last_audit_time + MISSING_INPUT_AUDIT_DELAY_SECS < Time.now)
        sent_audit = false

        # audit missing inputs, if necessary.
        missing_inputs_executables = {}
        pending_executables.each do |e|
          # names of missing inputs are available from RightScripts.
          missing_input_names = []
          if e.is_a?(RightScale::RightScriptInstantiation)
            e.parameters.each { |key, value| missing_input_names << key unless value }
          end
          last_missing_input_names = last_missing_inputs[:executables][e.nickname]
          if audit_missing_inputs || last_missing_input_names != missing_input_names
            title = RightScale::RightScriptsCookbook.recipe_title(e.nickname)
            if missing_input_names.empty?
              @audit.append_info("Waiting for missing inputs which are used by #{title}.")
            else
              @audit.append_info("Waiting for the following missing inputs which are used by #{title}: #{missing_input_names.join(", ")}")
            end
            sent_audit = true
          end
          missing_inputs_executables[e.nickname] = missing_input_names
        end

        # audit any executables which now have all inputs.
        last_missing_inputs[:executables].each_key do |nickname|
          unless missing_inputs_executables[nickname]
            title = RightScale::RightScriptsCookbook.recipe_title(nickname)
            @audit.append_info("The inputs used by #{title} which had been missing have now been resolved.")
            sent_audit = true
          end
        end
        last_missing_inputs[:executables] = missing_inputs_executables
        last_missing_inputs[:last_audit_time] = Time.now if sent_audit

        # schedule retry to retrieve missing inputs.
        EM.add_timer(MISSING_INPUT_RETRY_DELAY_SECS) { retrieve_missing_inputs(bundle, last_missing_inputs, &cb) }
      end
    end

    req.errback do |res|
      strand('Failed to retrieve missing inputs', res)
    end

    req.run
  end

  # Creates a new sequence for the given context.
  #
  # === Parameters
  # context(RightScale::OperationContext):: context
  #
  # === Return
  # sequence(RightScale::ExecutableSequenceProxy):: new sequence
  def create_sequence(context)
    return RightScale::ExecutableSequenceProxy.new(context)
  end

  # Retrieve and run boot scripts
  #
  # === Return
  # true:: Always return true
  def run_boot_bundle(bundle)
    @got_boot_bundle = true

    # Force full converge on boot so that Chef state gets persisted
    context = RightScale::OperationContext.new(bundle, @audit)
    sequence = create_sequence(context)
    sequence.callback do
      if patch = sequence.inputs_patch && !patch.empty?
        payload = {:agent_identity => @agent_identity, :patch => patch}
        send_push('/updater/update_inputs', payload)
      end
      @audit.update_status("boot completed: #{bundle}")
      yield success_result
    end
    sequence.errback  do
      @audit.update_status("boot failed: #{bundle}")
      yield error_result('Failed to run boot bundle')
    end

    begin
      sequence.run
    rescue Exception => e
      msg = 'Execution of Chef boot sequence failed'
      RightScale::Log.error(msg, e, :trace)
      strand(RightScale::Log.format(msg, e))
    end

    true
  end

  # Recovers from an aborted decommission.
  #
  # === Parameters
  # user_id(int):: user id or zero or nil
  # skip_db_update(Boolean):: true to skip db update after shutdown
  # kind(String):: 'reboot', 'stop' or 'terminate'
  #
  # === Return
  # always true
  def recover_decommission(user_id, skip_db_update, kind)
    # skip running decommission bundle again to avoid repeating the failure
    # which caused the previous decommission to kill the agent. log this
    # strange situation and go directly to instance shutdown.
    RightScale::Log.warning("Instance has recovered from an aborted decommission and will perform " +
                            "the last requested shutdown: #{kind}")
    RightScale::InstanceState.shutdown(user_id, skip_db_update, kind)
    true
  rescue Exception => e
    RightScale::Log.error("Failed recovering from aborted decommission", e, :trace)
    true
  end

end
