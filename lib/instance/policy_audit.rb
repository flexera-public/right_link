#--
# Copyright (c) 2012 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale, Inc. and
# the licensee.
#++

module RightScale

  class PolicyAudit
    # AuditProxy
    attr_accessor :audit

    # Creates a PolicyAudit to wrap AuditProxy
    #
    # === Parameters
    # audit(AuditProxy):: the audit that pertains to the bundle
    def initialize(audit)
      @audit = audit
    end

    # # See AuditProxy::update_status
    #
    # === Parameters
    # status(String):: New audit entry status
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def update_status(status, options={})
      true
    end

    # See AuditProxy::append_create_new_section
    #
    # === Parameters
    # title(String):: Title of new audit section, will replace audit status as well
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def create_new_section(title, options={})
      RightScale::Log.info title
      true
    end

    # See AuditProxy::append_info
    #
    # === Parameters
    # text(String):: Informational text to append to audit entry
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def append_info(text, options={})
      true
    end

    # See AuditProxy::append_error
    #
    # === Parameters
    # text(String):: Error text to append to audit entry
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def append_error(text, options={})
      @audit.append_error(text, options)
    end

    # See AuditProxy::append_output
    #
    # === Parameters
    # text(String):: Output to append to audit entry
    #
    # === Return
    # true:: Always return true
    def append_output(text)
      RightScale::Log.info text
      true
    end

  end

end