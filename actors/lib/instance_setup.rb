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
  include RightScale::RightLinkLogHelpers
  include RightScale::OperationResultHelpers

  expose :report_state

  # Amount of seconds to wait between set_r_s_version calls attempts
  RECONNECT_DELAY = 5

  # Delay enough time for attach/detach state in core to refresh
  VOLUME_RETRY_SECONDS = 15  # minimum retry time as recommended in docs when volumes are changing by automation

  # Max retries for attaching/detaching a given volume.
  MAX_VOLUME_ATTEMPTS = 8  # 8 * 15 seconds = 2 minutes

  # Amount of seconds to wait before shutting down if boot hasn't completed
  SUICIDE_DELAY = 45 * 60

  # Tag set on instances that are part of an array
  AUTO_LAUNCH_TAG ='rs_launch:type=auto'

  class InvalidResponse < Exception; end
  class UnexpectedState < Exception; end
  class UnsupportedDeviceName < Exception; end

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
      EM.next_tick { RightScale::MapperProxy.instance.initialize_offline_queue { init_boot } }
    else
      RightScale::MapperProxy.instance.initialize_offline_queue
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
    payload = {:agent_identity => @agent_identity,
               :r_s_version    => RightScale::RightLinkConfig.protocol_version,
               :resource_uid   => RightScale::InstanceState.resource_uid}
    # Do not allow this request to be retried because it is not idempotent
    send_persistent_request("/booter/declare", payload, nil, :offline_queueing => true) do |r|
      res = result_from(r)
      if res.success?
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

  # Manages planned volumes by caching planned volume state and then ensuring
  # volumes have been reattached in a predictable order for proper assignment
  # of local drives.
  #
  # === Parameters
  # block(Proc):: continuation callback for when volume management is complete.
  #
  # === Return
  # result(Boolean):: true if successful
  def manage_planned_volumes(&block)
    # state may have changed since timer calling this method was added, so
    # ensure we are still booting (and not stranded).
    return if RightScale::InstanceState.value == 'stranded'

    # query for planned volume mappings belonging to instance.
    last_mappings = RightScale::InstanceState.planned_volume_state.mappings || []
    payload = {:agent_identity => @agent_identity}
    send_retryable_request("/storage_valet/get_planned_volume_mappings", payload) do |r|
      res = result_from(r)
      if res.success?
        begin
          mappings = merge_planned_volume_mappings(last_mappings, res.content) { |mapping| is_device_valid?(mapping[:device]) }
          RightScale::InstanceState.planned_volume_state.mappings = mappings
          if mappings.empty?
            # no volumes requiring management.
            block.call if block
          else
            # must do some management if any volumes are not 'assigned'
            if mappings.find { |mapping| mapping[:management_status] != 'assigned' }
              # must detach all 'attached' volumes if any are attached (or
              # attaching) but not yet managed on the instance side. this is the
              # only way to ensure they receive the correct device names.
              detachable_volume_count = mappings.count { |mapping| is_attached_volume_unmanaged?(mapping) }
              if detachable_volume_count >= 1
                mappings.each do |mapping|
                  if is_attached_volume_unmanaged?(mapping)
                    detach_planned_volume(mapping) do
                      detachable_volume_count -= 1
                      if 0 == detachable_volume_count
                        # add a timer to resume volume management later and pass the
                        # block for continuation afterward (unless detachment stranded).
                        log_info("Waiting for volumes to detach for management purposes. Retrying in #{VOLUME_RETRY_SECONDS} seconds...")
                        EM.add_timer(VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
                      end
                    end
                  end
                end
              else
                mappings.each do |mapping|
                  case mapping[:volume_status]
                  when 'detached', 'detaching'
                    # attach next volume and go around again.
                    attach_planned_volume(mapping) do
                      log_info("Waiting for volume #{mapping[:volume_id]} to attach. Retrying in #{VOLUME_RETRY_SECONDS} seconds...")
                      EM.add_timer(VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
                    end
                    break  # out of mappings.each
                  when 'attached', 'attaching'
                    # assign next volume and go around again.
                    if mapping[:management_status] != 'assigned'
                      manage_volume_device_assignment(mapping) do
                        # we can move on to next volume 'immediately' unless the
                        # mapping requires a retry.
                        if mapping[:management_status] == 'assigned'
                          EM.next_tick { manage_planned_volumes(&block) }
                        else
                          log_info("Waiting for volume #{mapping[:volume_id]} to initialize using device #{mapping[:device]}. Retrying in #{VOLUME_RETRY_SECONDS} seconds...")
                          EM.add_timer(VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
                        end
                      end
                      break  # out of mappings.each
                    end
                  else
                    # handle 'deleted', etc.
                    strand("State of volume #{mapping[:volume_id]} was unexpected: #{mapping[:volume_status]}")
                  end
                end
              end
            else
              # all volume mappings have been assigned and so we can proceed.
              block.call if block
            end
          end
        rescue Exception => e
          strand(e)
        end
      else
        strand("Failed to retrieve planned volume mappings", res)
      end
    end
  end

  # Detaches the planned volume given by its mapping.
  #
  # === Parameters
  # mapping(Hash):: details of planned volume
  def detach_planned_volume(mapping)
    payload = {:agent_identity => @agent_identity, :device => mapping[:device]}
    log_info("Detaching volume intended for #{mapping[:device]} for management purposes.")
    send_retryable_request("/storage_valet/detach_volume", payload) do |r|
      res = result_from(r)
      if res.success?
        mapping[:volume_status] = 'detaching'
        mapping[:management_status] = 'detached'
        mapping[:attempts] = nil
        yield if block_given?
      else
        # volume could already be detaching or have been deleted
        # which we can't see because of latency; go around again
        # and check state of volume later.
        log_info("Received retry for detaching device #{mapping[:device]}") if res.retry?
        log_error("Failed to detach device #{mapping[:device]}: #{res.content}") if res.error?
        mapping[:attempts] ||= 0
        mapping[:attempts] += 1
        if mapping[:attempts] >= MAX_VOLUME_ATTEMPTS
          strand("Exceded maximum of #{MAX_VOLUME_ATTEMPTS} attempts detaching device #{mapping[:device]}")
        else
          yield if block_given?
        end
      end
    end
  end

  # Attaches the planned volume given by its mapping.
  #
  # === Parameters
  # mapping(Hash):: details of planned volume
  def attach_planned_volume(mapping)
    # preserve the initial list of disks/volumes before attachment for comparison later.
    vm = RightScale::RightLinkConfig[:platform].volume_manager
    RightScale::InstanceState.planned_volume_state.disks ||= vm.disks
    RightScale::InstanceState.planned_volume_state.volumes ||= vm.volumes

    # attach.
    payload = {:agent_identity => @agent_identity, :volume_id => mapping[:volume_id], :device => mapping[:device]}
    @audit.append_info("Attaching volume #{mapping[:volume_id]} using device \"#{mapping[:device]}\".")
    send_retryable_request("/storage_valet/attach_volume", payload) do |r|
      res = result_from(r)
      if res.success?
        mapping[:volume_status] = 'attaching'
        mapping[:management_status] = 'attached'
        mapping[:attempts] = nil
        yield if block_given?
      else
        # volume could already be attaching or have been deleted
        # which we can't see because of latency; go around again
        # and check state of volume later.
        log_info("Received retry for attaching volume #{mapping[:volume_id]} using device \"#{mapping[:device]}\".") if res.retry?
        log_error("Failed to attach volume #{mapping[:volume_id]} using device #{mapping[:device]}: #{res.content}") if res.error?
        mapping[:attempts] ||= 0
        mapping[:attempts] += 1
        if mapping[:attempts] >= MAX_VOLUME_ATTEMPTS
          strand("Exceeded maximum of #{MAX_VOLUME_ATTEMPTS} attempts attaching device #{mapping[:device]}")
        else
          yield if block_given?
        end
      end
    end
  end

  # Manages device assignment for volumes with considerations for formatting
  # blank attached volumes.
  #
  # === Parameters
  # mapping(Hash):: details of planned volume
  def manage_volume_device_assignment(mapping)

    # only managed volumes should be in an attached state ready for assignment.
    unless 'attached' == mapping[:management_status]
      raise UnexpectedState.new("The volume #{mapping[:volume_id]} for device #{mapping[:device]} was in an unexpected managed state: #{mapping[:management_status]}")
    end

    # check for changes in disks.
    last_disks = RightScale::InstanceState.planned_volume_state.disks
    last_volumes = RightScale::InstanceState.planned_volume_state.volumes
    vm = RightScale::RightLinkConfig[:platform].volume_manager
    current_disks = vm.disks
    current_volumes = vm.volumes

    # correctly managing device assignment requires expecting precise changes
    # to disks and volumes. any deviation from this requires a retry.
    succeeded = false
    if new_disk = find_distinct_item(current_disks, last_disks, :index)
      # if the new disk as no partitions, then we will format and assign device.
      if vm.partitions(new_disk[:index]).empty?
        @audit.append_info("Creating primary partition and formatting device \"#{mapping[:device]}\".")
        vm.format_disk(new_disk[:index], mapping[:device])
        succeeded = true
      else
        @audit.append_info("Preparing device \"#{mapping[:device]}\" for use.")
        new_volume = find_distinct_item(current_volumes, last_volumes, :device)
        unless new_volume
          vm.online_disk(new_disk[:index])
          current_volumes = vm.volumes
          new_volume = find_distinct_item(current_volumes, last_volumes, :device)
        end
        if new_volume
          vm.assign_device(new_volume[:index], mapping[:device]) unless new_volume[:device] == mapping[:device]
          succeeded = true
        end
      end
    end

    # retry only if still not assigned.
    if succeeded
      # volume is (finally!) assigned to correct device name.
      mapping[:management_status] = 'assigned'
      mapping[:attempts] = nil

      # reset cached volumes/disks for next attempt (to attach), if any.
      RightScale::InstanceState.planned_volume_state.disks = nil
      RightScale::InstanceState.planned_volume_state.volumes = nil

      # continue.
      yield if block_given?
    else
      mapping[:attempts] ||= 0
      mapping[:attempts] += 1
      if mapping[:attempts] >= MAX_VOLUME_ATTEMPTS
        strand("Exceeded maximum of #{MAX_VOLUME_ATTEMPTS} attempts attaching device #{mapping[:device]}")
      else
        yield if block_given?
      end
    end
  rescue Exception => e
    strand(e)
  end

  # Determines a single, unique item (hash) by given key in the current
  # list which does not appear in the last list, if any. finds nothing if
  # multiple new items appear. This is useful for inspecting lists of
  # disks/volumes to determine when a new item appears.
  #
  # === Parameter
  # current_list(Array):: current list
  # last_list(Array):: last list
  # key(Symbol):: key used to uniquely identify items
  #
  # === Return
  # result(Hash):: item in current list which does not appear in last list or nil
  def find_distinct_item(current_list, last_list, key)
    if current_list.size == last_list.size + 1
      unique_values = current_list.map { |item| item[key] } - last_list.map { |item| item[key] }
      if unique_values.size == 1
        unique_value = unique_values[0]
        return current_list.find { |item| item[key] == unique_value }
      end
    end
    return nil
  end

  # Determines if the given volume is in an attached (or attaching) state and
  # not yet managed (in a managed state). Note that we can assign drive letters
  # to 'attaching' volumes because they may appear locally before the repository
  # can update their status to 'attached'.
  #
  # === Return
  # result(Boolean):: true if volume is attached and unassigned
  def is_attached_volume_unmanaged?(mapping)
    case mapping[:volume_status]
    when 'attached', 'attaching'
      mapping[:management_status].nil?
    else
      false
    end
  end

  # Merges mappings from query with any last known mappings which may have a
  # locally persisted state which needs to be evaluated.
  def merge_planned_volume_mappings last_mappings, current_mappings, &block
    results = []

    # merge latest mappings with last mappings, if any.
    current_mappings.each do |mapping|
      mapping = RightScale::SerializationHelper.symbolize_keys(mapping)
      valid_mapping = mapping[:device] && mapping[:volume_id] && mapping[:volume_status]
      raise InvalidResponse.new("Reponse for volume mapping was invalid: #{mapping.inspect}") unless valid_mapping

      # ignore any mention of "/dev/sda1" because it represents the boot
      # volume (for both Windows and Linux) and should never be 'managed'.
      #
      # FIX: filter this on the server side?
      unless mapping[:device] == "/dev/sda1"
        # check that device name is valid
        if block.call(mapping[:device])
          last_mapping = last_mappings.find { |last_mapping| last_mapping[:volume_id] == mapping[:volume_id] }
          if last_mapping
            # if device assignment has changed then we must start over (we can't prevent the user from doing this).
            if last_mapping[:device] != mapping[:device]
              last_mapping[:device] = mapping[:device]
              last_mapping[:management_status] = nil
            end
            last_mapping[:volume_status] = mapping[:volume_status]
            mapping = last_mapping
          end
          results << mapping
        else
          raise UnsupportedDeviceName.new("Cannot mount a volume using device name #{device}.")
        end
      end
    end

    # preserve any last mappings which do not appear in current mappings by
    # assuming that they are 'detached' to support a limitation of the initial
    # query implementation.
    last_mappings.each do |last_mapping|
      mapping = results.find { |mapping| mapping[:volume_id] == last_mapping[:volume_id] }
      unless mapping
        last_mapping[:volume_status] = 'detached'
        results << last_mapping
      end
    end

    return results
  end

  # Determines if the given device name is valid for current platform.
  #
  # === Return
  # result(Boolean):: true if device name is valid
  def is_device_valid?(device)
    return RightScale::RightLinkConfig[:platform].volume_manager.is_attachable_volume_path?(device)
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
