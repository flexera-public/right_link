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

module RightScale

  class VolumeManagement
    # Delay enough time for attach/detach state in core to refresh
    VOLUME_RETRY_SECONDS = 15  # minimum retry time as recommended in docs when volumes are changing by automation

    # Max retries for attaching/detaching a given volume.
    MAX_VOLUME_ATTEMPTS = 8  # 8 * 15 seconds = 2 minutes

    class InvalidResponse < Exception; end
    class UnexpectedState < Exception; end
    class UnsupportedMountPoint < Exception; end
  end

  # Provides helpers for platforms which must manage volume attachments on the
  # instance side.
  module VolumeManagementHelpers

    protected

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
      send_retryable_request("/storage_valet/get_planned_volumes", payload) do |r|
        res = result_from(r)
        if res.success?
          begin
            mappings = merge_planned_volume_mappings(last_mappings, res.content)
            RightScale::InstanceState.planned_volume_state.mappings = mappings
            if mappings.empty?
              # no volumes requiring management.
              @audit.append_info("This instance has no planned volumes.")
              block.call if block
            elsif (detachable_volume_count = mappings.count { |mapping| is_unmanaged_attached_volume?(mapping) }) >= 1
              # must detach all 'attached' volumes if any are attached (or
              # attaching) but not yet managed on the instance side. this is the
              # only way to ensure they receive the correct device names.
              mappings.each do |mapping|
                if is_unmanaged_attached_volume?(mapping)
                  detach_planned_volume(mapping) do
                    unless RightScale::InstanceState.value == 'stranded'
                      detachable_volume_count -= 1
                      if 0 == detachable_volume_count
                        # add a timer to resume volume management later and pass the
                        # block for continuation afterward (unless detachment stranded).
                        log_info("Waiting for volumes to detach for management purposes. "\
                                 "Retrying in #{VolumeManagement::VOLUME_RETRY_SECONDS} seconds...")
                        EM.add_timer(VolumeManagement::VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
                      end
                    end
                  end
                end
              end
            elsif mapping = mappings.find { |mapping| is_detaching_volume?(mapping) }
              # we successfully requested detachment but status has not
              # changed to reflect this yet.
              log_info("Waiting for volume #{mapping[:volume_id]} to fully detach. "\
                       "Retrying in #{VolumeManagement::VOLUME_RETRY_SECONDS} seconds...")
              EM.add_timer(VolumeManagement::VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
            elsif mapping = mappings.find { |mapping| is_managed_attaching_volume?(mapping) }
              log_info("Waiting for volume #{mapping[:volume_id]} to fully attach. Retrying in #{VolumeManagement::VOLUME_RETRY_SECONDS} seconds...")
              EM.add_timer(VolumeManagement::VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
            elsif mapping = mappings.find { |mapping| is_managed_attached_unassigned_volume?(mapping) }
              manage_volume_device_assignment(mapping) do
                unless RightScale::InstanceState.value == 'stranded'
                  # we can move on to next volume 'immediately' if volume was
                  # successfully assigned its device name.
                  if mapping[:management_status] == 'assigned'
                    EM.next_tick { manage_planned_volumes(&block) }
                  else
                    log_info("Waiting for volume #{mapping[:volume_id]} to initialize using \"#{mapping[:mount_points].first}\". "\
                             "Retrying in #{VolumeManagement::VOLUME_RETRY_SECONDS} seconds...")
                    EM.add_timer(VolumeManagement::VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
                  end
                end
              end
            elsif mapping = mappings.find { |mapping| is_detached_volume?(mapping) }
              attach_planned_volume(mapping) do
                unless RightScale::InstanceState.value == 'stranded'
                  unless mapping[:attempts]
                    @audit.append_info("Attached volume #{mapping[:volume_id]} using \"#{mapping[:mount_points].first}\".")
                    log_info("Waiting for volume #{mapping[:volume_id]} to appear using \"#{mapping[:mount_points].first}\". "\
                             "Retrying in #{VolumeManagement::VOLUME_RETRY_SECONDS} seconds...")
                  end
                  EM.add_timer(VolumeManagement::VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
                end
              end
            elsif mapping = mappings.find { |mapping| is_unmanageable_volume?(mapping) }
              strand("State of volume #{mapping[:volume_id]} was unmanageable: #{mapping[:volume_status]}")
            else
              # all volumes are managed and have been assigned and so we can proceed.
              block.call if block
            end
          rescue Exception => e
            strand(e)
          end
        elsif res.retry?
          log_info("Received retry for getting planned volume mappings: #{res.content}")
          EM.add_timer(VolumeManagement::VOLUME_RETRY_SECONDS) { manage_planned_volumes(&block) }
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
      payload = {:agent_identity => @agent_identity, :device_name => mapping[:device_name]}
      log_info("Detaching volume #{mapping[:volume_id]} for management purposes.")
      send_retryable_request("/storage_valet/detach_volume", payload) do |r|
        res = result_from(r)
        if res.success?
          # don't set :volume_status here as that should only be queried
          mapping[:management_status] = 'detached'
          mapping[:attempts] = nil
          yield if block_given?
        else
          # volume could already be detaching or have been deleted
          # which we can't see because of latency; go around again
          # and check state of volume later.
          log_info("Received retry for detaching volume #{mapping[:volume_id]}.") if res.retry?
          log_error("Failed to detach volume #{mapping[:volume_id]}: #{res.content}") if res.error?
          mapping[:attempts] ||= 0
          mapping[:attempts] += 1
          # retry indefinitely so long as core api instructs us to retry or else fail after max attempts.
          if mapping[:attempts] >= VolumeManagement::MAX_VOLUME_ATTEMPTS && res.error?
            strand("Exceeded maximum of #{VolumeManagement::MAX_VOLUME_ATTEMPTS} attempts detaching volume #{mapping[:volume_id]} with error: #{res.content}")
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
      payload = {:agent_identity => @agent_identity, :volume_id => mapping[:volume_id], :device_name => mapping[:device_name]}
      log_info("Attaching volume #{mapping[:volume_id]}.")
      send_retryable_request("/storage_valet/attach_volume", payload) do |r|
        res = result_from(r)
        if res.success?
          # don't set :volume_status here as that should only be queried
          mapping[:management_status] = 'attached'
          mapping[:attempts] = nil
          yield if block_given?
        else
          # volume could already be attaching or have been deleted
          # which we can't see because of latency; go around again
          # and check state of volume later.
          log_info("Received retry for attaching volume #{mapping[:volume_id]}.") if res.retry?
          log_error("Failed to attach volume #{mapping[:volume_id]}: #{res.content}") if res.error?
          mapping[:attempts] ||= 0
          mapping[:attempts] += 1
          # retry indefinitely so long as core api instructs us to retry or else fail after max attempts.
          if mapping[:attempts] >= VolumeManagement::MAX_VOLUME_ATTEMPTS && res.error?
            strand("Exceeded maximum of #{VolumeManagement::MAX_VOLUME_ATTEMPTS} attempts attaching volume #{mapping[:volume_id]} with error: #{res.content}")
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
        raise VolumeManagement::UnexpectedState.new("The volume #{mapping[:volume_id]} was in an unexpected managed state: #{mapping.inspect}")
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
          # FIX: ignore multiple mount points for simplicity and only only create
          # a single primary partition for the first mount point.
          # if we had the UI for it, then the user would probably specify
          # partition sizes as a percentage of disk size and associate those with
          # mount points formatted optionally specifying file system, label, etc.
          @audit.append_info("Creating primary partition and formatting \"#{mapping[:mount_points].first}\".")
          vm.format_disk(new_disk[:index], mapping[:mount_points].first)
          succeeded = true
        else
          # FIX: ignoring multiple existing partitiions on a disk (which should
          # result in multiple new volumes appearing when the disk comes online)
          # for simplicity until we have a UI supporting multiple mount points.
          @audit.append_info("Preparing \"#{mapping[:mount_points].first}\" for use.")
          new_volume = find_distinct_item(current_volumes, last_volumes, :device)
          unless new_volume
            vm.online_disk(new_disk[:index])
            current_volumes = vm.volumes
            new_volume = find_distinct_item(current_volumes, last_volumes, :device)
          end
          if new_volume
            # prefer selection by existing device because it is more reliable in Windows 2003 case.
            unless new_volume[:device] && (0 == new_volume[:device].casecmp(mapping[:mount_points].first))
              device_or_index_to_select = new_volume[:device] || new_volume[:index]
              vm.assign_device(device_or_index_to_select, mapping[:mount_points].first)
            end
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
        if mapping[:attempts] >= VolumeManagement::MAX_VOLUME_ATTEMPTS
          strand("Exceeded maximum of #{VolumeManagement::MAX_VOLUME_ATTEMPTS} attempts waiting for volume #{mapping[:volume_id]} to be in a managable state.")
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
    def is_unmanaged_attached_volume?(mapping)
      case mapping[:volume_status]
      when 'attached', 'attaching'
        mapping[:management_status].nil?
      else
        false
      end
    end

    # Determines if the given volume is detaching regardless of whether detachment
    # was managed (will adopt any detatching volumes).
    #
    # === Return
    # result(Boolean):: true if volume is detaching
    def is_detaching_volume?(mapping)
      case mapping[:volume_status]
      when 'detaching'
        true
      when 'attached', 'attaching'
        # also detaching if we have successfully requested detachment but volume
        # status does not yet reflect this change.
        'detached' == mapping[:management_status]
      else
        false
      end
    end

    # Determines if the given volume is detached regardless of whether detachment
    # was managed (will adopt any detatched volumes).
    #
    # === Return
    # result(Boolean):: true if volume is detaching
    def is_detached_volume?(mapping)
      # detached by volume status unless we have successfully requested attachment
      # and volume status does not yet reflect this change. an unmanaged volume
      # can also be detached.
      return 'detached' == mapping[:volume_status] && 'attached' != mapping[:management_status]
    end

    # Determines if the given volume is attaching and managed (indicating that we
    # requested attachment).
    #
    # === Return
    # result(Boolean):: true if volume is managed and attaching
    def is_managed_attaching_volume?(mapping)
      return 'attached' == mapping[:management_status] && 'attached' != mapping[:volume_status]
    end

    # Determines if the given volume is attached and managed (indicating that we
    # requested attachment) but not yet assigned its device name.
    #
    # === Return
    # result(Boolean):: true if volume is managed, attached and unassigned
    def is_managed_attached_unassigned_volume?(mapping)
      return 'attached' == mapping[:volume_status] && 'attached' == mapping[:management_status]
    end

    # Determines if the given volume is in an unmanageable state (such as
    # 'deleted').
    #
    # === Return
    # result(Boolean):: true if volume is managed but unrecoverable
    def is_unmanageable_volume?(mapping)
      case mapping[:volume_status]
      when 'attached', 'attaching', 'detached', 'detaching'
        false
      else
        true
      end
    end

    # Merges mappings from query with any last known mappings which may have a
    # locally persisted state which needs to be evaluated.
    #
    # === Parameters
    # last_mappings(Array):: previously merged mappings or empty
    # current_mappings(Array):: current unmerged mappings or empty
    #
    # === Returns
    # results(Array):: array of hashes representing merged mappings
    def merge_planned_volume_mappings(last_mappings, current_planned_volumes)
      results = []
      vm = RightScale::RightLinkConfig[:platform].volume_manager

      # merge latest mappings with last mappings, if any.
      current_planned_volumes.each do |planned_volume|
        raise VolumeManagement::InvalidResponse.new("Reponse for volume mapping was invalid: #{mapping.inspect}") unless planned_volume.is_valid?
        if mount_point = planned_volume.mount_points.find { |mount_point| false == vm.is_attachable_volume_path?(mount_point) }
          raise VolumeManagement::UnsupportedMountPoint.new("Cannot mount a volume using \"#{mount_point}\".")
        end

        mapping = {:volume_id => planned_volume.volume_id,
                   :device_name => planned_volume.device_name,
                   :volume_status => planned_volume.volume_status,
                   :mount_points => planned_volume.mount_points.dup}
        if last_mapping = last_mappings.find { |last_mapping| last_mapping[:volume_id] == mapping[:volume_id] }
          # if device name or mount point(s) have changed then we must start
          # over (we can't prevent the user from doing this).
          if last_mapping[:device_name] != mapping[:device_name] || last_mapping[:mount_points] != mapping[:mount_points]
            last_mapping[:device_name] = mapping[:device_name]
            last_mapping[:mount_points] = mapping[:mount_points].dup
            last_mapping[:management_status] = nil
          end
          last_mapping[:volume_status] = mapping[:volume_status]
          mapping = last_mapping
        end
        results << mapping
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

  end

end
