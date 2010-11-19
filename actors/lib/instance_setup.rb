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

  include RightScale::Actor

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
    RightScale::RightLinkLog.force_debug if RightScale::DevState.enabled?
    
    # Schedule boot sequence, don't run it now so agent is registered first
    if RightScale::InstanceState.value == 'booting'
      EM.next_tick { RightScale::RequestForwarder.instance.init { init_boot } }
    else
      RightScale::RequestForwarder.instance.init
    end

    # Setup suicide timer which will cause instance to shutdown if the rs_launch:type=auto tag
    # is set and the instance has not gotten its boot bundle after SUICIDE_DELAY seconds and this is 
    # the first time this instance boots
    @suicide_timer = EM::Timer.new(SUICIDE_DELAY) do
      if RightScale::InstanceState.startup_tags.include?(AUTO_LAUNCH_TAG) && !@got_boot_bundle
        msg = "Shutting down after having tried to boot for #{SUICIDE_DELAY / 60} minutes"
        RightScale::RightLinkLog.error(msg)
        @audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if @audit
        RightScale::Platform.controller.shutdown 
      end
    end if RightScale::InstanceState.initial_boot?

  end

  # Retrieve current instance state
  #
  # === Return
  # state(RightScale::OperationResult):: Success operation result containing instance state
  def report_state
    state = RightScale::OperationResult.success(RightScale::InstanceState.value)
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
      RightScale::RequestForwarder.instance.enable_offline_mode
    else
      RightScale::RequestForwarder.instance.disable_offline_mode
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
    options = { :agent_identity => @agent_identity,
                :r_s_version    => RightScale::RightLinkConfig.protocol_version,
                :resource_uid   => RightScale::InstanceState.resource_uid }
    RightScale::RequestForwarder.instance.request('/booter/declare', options) do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        enable_managed_login
      else
        if res.retry?
          RightScale::RightLinkLog.info("RightScale not ready, retrying in #{RECONNECT_DELAY} seconds...")
        else
          RightScale::RightLinkLog.warn("Failed to contact RightScale: #{res.content}, retrying in #{RECONNECT_DELAY} seconds...")
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
      boot
    else
      request('/booter/get_login_policy', {:agent_identity => @agent_identity}) do |r|
        res = RightScale::OperationResult.from_results(r)
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
            audit.append_error("Error applying login policy: #{e.message}", :category => RightScale::EventCategories::CATEGORY_ERROR)
            RightScale::RightLinkLog.error("#{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}")
          end
        else
          RightScale::RightLinkLog.error("Could not get login policy: #{res.content}")
        end

        boot
      end
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
                RightScale::InstanceState.value = 'operational'
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
    RightScale::InstanceState.value = 'stranded'
    msg += ": #{res.content}" if res && res.content
    @audit.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR) if @audit
    true
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
        RightScale::RightLinkLog.error(e.message)
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
      options = { :agent_identity => @agent_identity, :audit_id => @audit.audit_id }
      request("/booter/get_boot_bundle", options) do |r|
        res = RightScale::OperationResult.from_results(r)
        if res.success?
          bundle = res.content
          if bundle.executables.any? { |e| !e.ready }
            retrieve_missing_inputs(bundle) { cb.call(RightScale::OperationResult.success(bundle)) }
          else
            yield RightScale::OperationResult.success(bundle)
          end
        else
          msg = "Failed to retrieve boot scripts"
          msg += ": #{res.content}" if res.content
          yield RightScale::OperationResult.error(msg)
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
    RightScale::RequestForwarder.instance.request('/booter/get_missing_attributes', { :agent_identity => @agent_identity,
                                                                                      :scripts_ids    => scripts_ids,
                                                                                      :recipes_ids    => recipes_ids }) do |r|
      res = RightScale::OperationResult.from_results(r)
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

  # Retrieve and run boot scripts
  #
  # === Return
  # true:: Always return true
  def run_boot_bundle(bundle)
    @got_boot_bundle = true

    # Force full converge on boot so that Chef state gets persisted
    context = RightScale::OperationContext.new(bundle, @audit)
    sequence = RightScale::ExecutableSequenceProxy.new(context)
    sequence.callback do
      if patch = sequence.inputs_patch && !patch.empty?
        RightScale::RequestForwarder.instance.push('/updater/update_inputs', { :agent_identity => @agent_identity,
                                                                               :patch          => patch })
      end
      @audit.update_status("boot completed: #{bundle}")
      yield RightScale::OperationResult.success
    end
    sequence.errback  do
      @audit.update_status("boot failed: #{bundle}")
      yield RightScale::OperationResult.error("Failed to run boot bundle")
    end

    begin
      sequence.run
    rescue Exception => e
      msg = "Execution of Chef boot sequence failed with exception: #{e.message}"
      RightScale::RightLinkLog.error(msg + "\n" + e.backtrace.join("\n"))
      strand(msg)
    end

    true
  end

end
