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
#

module RightScale

  # Boot, operation or decommission executable bundle, includes:
  # * RightScripts with associated packages, parameters and attachments
  # * Recipes with associated JSON
  # * Cookbook repositories with associated attributes
  # * Audit id
  # Recipes and RightScripts instantiations are interspersed and ordered into one collection
  # The instance agent can use the audit created by the core agent to audit messages
  # associated with the processing of the software repositories
  class ExecutableBundle

    include Serializable

    # (Array) Collection of RightScripts and chef recipes instantiations
    attr_accessor :executables

    # (Array) Chef cookbook repositories
    attr_accessor :cookbook_repositories

    # (Integer) ID of corresponding audit entry
    attr_accessor :audit_id

    # (Boolean) Whether a full or partial converge should be done
    # Note: Obsolete as of r_s_version 8, kept for backwards compatibility
    attr_accessor :full_converge

    # (Array) Chef cookbooks
    attr_accessor :cookbooks

    def initialize(*args)
      @executables           = args[0]
      @cookbook_repositories = args[1] if args.size > 1
      @audit_id              = args[2] if args.size > 2
      @full_converge         = args[3] if args.size > 3
      @cookbooks             = args[4] if args.size > 4
    end

    # Array of serialized fields given to constructor
    def serialized_members
      [ @executables, @cookbook_repositories, @audit_id, @full_converge, @cookbooks ]
    end

    # Human readable representation
    #
    # === Return
    # desc(String):: Auditable description
    def to_s
      desc = @executables.collect { |e| e.nickname }.join(', ') if @executables
      desc ||= 'empty bundle'
    end

  end
end
