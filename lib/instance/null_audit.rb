# Copyright (c) 2012 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

module RightScale
  # audit entry that can be used to supress unwanted audits
  class NullAudit
    attr_accessor id

    def initialize(audit_id)
      @id = audit_id
    end

    # see AuditProxy::append_info
    def append_info(text, options={})
      # intentionally do nothing
    end
    
    # see AuditProxy::update_status
    def update_status(status, options={})
      # intentionally do nothing
    end
    
    # see AuditProxy::create_new_section
    def create_new_section(title, options = nil)
      # intentionally do nothing
    end

    # see AuditProxy::append_output
    def append_output(text, options = nil)
      # intentionally do nothing
    end
  end
end