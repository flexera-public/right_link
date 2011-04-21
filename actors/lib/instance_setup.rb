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

class InstanceSetup

  include RightScale::Actor
  include RightScale::RightLinkLogHelpers
  include RightScale::OperationResultHelpers
  include RightScale::ShutdownManagement::Helpers
  include RightScale::VolumeManagementHelpers

  expose :report_state

  # Amount of seconds to wait between set_r_s_version calls attempts
  RECONNECT_DELAY = 5

  # Amount of seconds to wait before shutting down if boot hasn't completed
  SUICIDE_DELAY = 45 * 60

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
    RightScale::RightLinkLog.force_debug if RightScale::CookState.dev_mode_enabled?

    # Schedule boot sequence, don't run it now so agent is registered first
    if RightScale::InstanceState.value == 'booting'
      EM.next_tick { init_boot }
    else
      RightScale::MapperProxy.instance.initialize_offline_queue
      RightScale::MapperProxy.instance.start_offline_queue
    end

    # Setup suicide timer which will cause instance to shutdown if the rs_launch:type=auto tag
    # is set and the instance has not gotten its boot bundle after SUICIDE_DELAY seconds and this is
    # the first time this instance boots
    @suicide_timer = EM::Timer.new(SUICIDE_DELAY) do
      if RightScale::InstanceState.startup_tags.include?(AUTO_LAUNCH_TAG) && !@got_boot_bundle
        msg = "Shutting down after having tried to boot for #{SUICIDE_DELAY / 60} minutes"
        log_error(msg)
        @audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if @audit
        RightScale::Platform.controller.shutdown
      end
    end if RightScale::InstanceState.initial_boot?

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
      RightScale::MapperProxy.instance.enable_offline_mode
    else
      RightScale::MapperProxy.instance.disable_offline_mode
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
    RightScale::MapperProxy.instance.initialize_offline_queue
    payload = {:agent_identity => @agent_identity,
               :r_s_version    => RightScale::RightLinkConfig.protocol_version,
               :resource_uid   => RightScale::InstanceState.resource_uid}
    # Do not allow this request to be retried because it is not idempotent
    send_persistent_request("/booter/declare", payload, nil, :offline_queueing => true) do |r|
      res = result_from(r)
      if res.success?
        RightScale::MapperProxy.instance.start_offline_queue
        enable_managed_login
      else
        if res.retry?
          log_info("RightScale not ready, retrying in #{RECONNECT_DELAY} seconds...")
        else
          log_warning("Failed to contact RightScale: #{res.content}, retrying in #{RECONNECT_DELAY} seconds...")
        end
        # Retry in RECONNECT_DELAY seconds, retry forever, nothing else we can do
        EM.add_timer(RECONNECT_DELAY) { init_boot }
      end
    end
    true
  end

  # Enable managed SSH for this instance, then continue with boot. Ensures that
  # managed SSH users can login to troubleshoot stranded and other 'interesting' events
  #
  # === Return
  # true:: Always return true
  def enable_managed_login
    if RightScale::Platform.windows? || RightScale::Platform.mac?
      boot_volumes
    else
      send_retryable_request("/booter/get_login_policy", {:agent_identity => @agent_identity}) do |r|
        res = result_from(r)
        if res.success?
          policy  = res.content
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
            log_error("Failed to enable managed login", e, :trace)
          end
        else
          log_error("Could not get login policy", res.content)
        end

        boot_volumes
      end
    end
  end

  # Retrieve software repositories and configure mirrors accordingly then proceed to
  # retrieving and running boot bundle.
  #
  # === Return
  # true:: Always return true
  def boot_volumes
    # managing planned volumes is currently only needed in Windows and only if
    # this is not a reboot scenario.
    if RightScale::Platform.windows? and not RightScale::InstanceState.reboot?
      RightScale::AuditProxy.create(@agent_identity, 'Planned volume management') do |audit|
        @audit = audit
        manage_planned_volumes do
          @audit = nil
          boot
        end
      end
    else
      boot
    end
    true
  end

  # Retrieve software repositories and configure mirrors accordingly then proceed to
  # retrieving and running boot bundle.
  #
  # === Return
  # true:: Always return true
  def boot
    send_retryable_request("/booter/get_repositories", @agent_identity) do |r|
      res = result_from(r)
      if res.success?
        @audit = RightScale::AuditProxy.new(res.content.audit_id)
        unless RightScale::Platform.windows? || RightScale::Platform.mac?
          reps = res.content.repositories
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
                RightScale::InstanceState.value = 'operational' unless shutdown_request.immediately?
                manage_shutdown_request(@audit)
              else
                strand("Failed to run boot sequence", boot_res)
              end
            end
          else
            strand("Failed to prepare boot bundle", prep_res)
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
  # msg(String):: Error message that will be audited and logged
  # res(RightScale::OperationResult):: Operation result with additional information
  #
  # === Return
  # true:: Always return true
  def strand(msg, res=nil)

    # attempt to provide details of exception or result which caused stranding.
    detailed = nil
    if msg.kind_of? Exception
      e = msg
      detailed = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
      msg = e.message
    end
    msg += ": #{res.content}" if res && res.content
    @audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if @audit
    log_error(detailed) if detailed

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
        log_error("Failed to configure repositories", e)
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
      send_retryable_request("/booter/get_boot_bundle", payload) do |r|
        res = result_from(r)
        if res.success?
          bundle = res.content
          if bundle.executables.any? { |e| !e.ready }
            retrieve_missing_inputs(bundle) { cb.call(success_result(bundle)) }
          else
            yield success_result(bundle)
          end
        else
          yield error_result(format_error("Failed to retrieve boot scripts", res.content))
        end
      end
    end
  end

  # Retrieve missing inputs for recipes and RightScripts stored in
  # @recipes and @scripts respectively, update recipe attributes, RightScript
  # parameters and ready fields (set ready field to true if attempt was successful,
  # false otherwise).
  # This is for environment variables that we are waiting on.
  # Retries forever.
  #
  # === Block
  # Continuation block, will be called once attempt to retrieve attributes is completed
  #
  # === Return
  # true:: Always return true
  def retrieve_missing_inputs(bundle, &cb)
    scripts = bundle.executables.select { |e| e.is_a?(RightScale::RightScriptInstantiation) }
    recipes = bundle.executables.select { |e| e.is_a?(RightScale::RecipeInstantiation) }
    scripts_ids = scripts.select { |s| !s.ready }.map { |s| s.id }
    recipes_ids = recipes.select { |r| !r.ready }.map { |r| r.id }
    payload = {:agent_identity => @agent_identity,
               :scripts_ids    => scripts_ids,
               :recipes_ids    => recipes_ids}
    send_retryable_request("/booter/get_missing_attributes", payload, nil, :offline_queueing => true) do |r|
      res = result_from(r)
      if res.success?
        res.content.each do |e|
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
          titles = pending_executables.map { |e| RightScale::RightScriptsCookbook.recipe_title(e.nickname) }
          @audit.append_info("Missing inputs for #{titles.join(", ")}, waiting...")
          sleep(20)
          retrieve_missing_inputs(bundle, &cb)
        end
      else
        strand("Failed to retrieve missing inputs", res)
      end
    end
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
        send_push("/updater/update_inputs", payload, nil, :offline_queueing => true)
      end
      @audit.update_status("boot completed: #{bundle}")
      yield success_result
    end
    sequence.errback  do
      @audit.update_status("boot failed: #{bundle}")
      yield error_result("Failed to run boot bundle")
    end

    begin
      sequence.run
    rescue Exception => e
      msg = "Execution of Chef boot sequence failed"
      log_error(msg, e, :trace)
      strand(format_error(msg, e))
    end

    true
  end

end
