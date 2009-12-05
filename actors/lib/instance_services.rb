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

class InstanceServices
  include Nanite::Actor

  expose :update_login_policy

  def initialize(agent_identity)
    @agent_identity = agent_identity
  end

  # Always return success, used for troubleshooting
  #
  # === Return
  # res<RightScale::OperationResult>:: Always returns success
  def update_login_policy(new_policy)
    status = nil
    
    request("/auditor/create_entry", :agent_identity=>@agent_identity, :summary=>'Updating managed login policy') do |r|
      res = RightScale::OperationResult.from_results(r)
      if res.success?
        auditor = RightScale::AuditorProxy.new(res.content)
      else
        RightScale::RightLinkLog.error("Could not create audit entry for policy update: #{res.content}")
        auditor = RightScale::AuditorProxy.new(nil)
      end

      begin
        audit = RightScale::LoginManager.instance.update_policy(new_policy)
        auditor.create_new_section("Managed login policy updated")
        auditor.append_info(audit)
        status = RightScale::OperationResult.success
      rescue Exception => e
        auditor.create_new_section('Failed to update managed login policy')
        auditor.append_error("Error applying policy: #{e.message}")
        RightScale::RightLinkLog.error("#{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}")
        status = RightScale::OperationResult.error("#{e.class.name} - #{e.message}")
      end            
    end

    status
  end

end
