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

class InstanceServices

  include RightScale::Actor
  include RightScale::OperationResultHelper

  expose :update_login_policy, :reboot

  def initialize(agent_identity)
    @agent_identity = agent_identity
  end

  # Apply a new SSH login policy to the instance.
  # Always return success, used for troubleshooting
  #
  # == Parameters:
  # @param [RightScale::LoginPolicy] new login policy to update the instance with
  #
  # == Returns:
  # @return [RightScale::OperationResult] Always returns success
  #
  def update_login_policy(new_policy)
    status = nil

    RightScale::AuditProxy.create(@agent_identity, 'Updating managed login policy') do |audit|
      begin
        RightScale::LoginManager.instance.update_policy(new_policy, @agent_identity) do |audit_content|
          if audit_content
            audit.create_new_section('Managed login policy updated', :category => RightScale::EventCategories::CATEGORY_SECURITY)
            audit.append_info(audit_content)
          end
        end
        status = success_result
      rescue Exception => e
        audit.create_new_section('Failed to update managed login policy', :category => RightScale::EventCategories::CATEGORY_SECURITY)
        audit.append_error("Error applying login policy: #{e.message}", :category => RightScale::EventCategories::CATEGORY_ERROR)
        RightScale::Log.error('Failed to update managed login policy', e, :trace)
        status = error_result("#{e.class.name}: #{e.message}")
      end
    end

    status
  end

  # Reboot the instance using local (OS) facility.
  #
  # @return [RightScale::OperationResult] Always returns success
  #
  def reboot(_)
    # Do reboot on next_tick so that have change to return result
    EM.next_tick do
      begin
        RightScale::Log.info('Initiate reboot using local (OS) facility')
        RightScale::RightHttpClient.instance.close(:receive)
        RightScale::Platform.controller.reboot
      rescue Exception => e
        RightScale::Log.error("Failed reboot", e, :trace)
      end
    end
    success_result
  end
end
