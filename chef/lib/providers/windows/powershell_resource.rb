#
# Copyright (c) 2010 RightScale Inc
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

require 'fileutils'
require 'chef/resource/script'

class Chef

  class Resource

    # Powershell chef resource.
    # Allows defining recipes which wrap Powershell v1.0 scripts.
    #
    # === Example
    # powershell "My Powershell Script" do
    #   source "write-output \"Running powershell v1.0 script\""
    # end
    class Powershell < Chef::Resource::Script

      # Initialize Powershell resource with default values
      #
      # === Parameters
      # name(String):: Nickname of Powershell
      # collection(Array):: Collection of included recipes
      # node(Chef::Node):: Node where resource will be used
      def initialize(name, run_context=nil)
        super(name, run_context)
        @resource_name = :powershell
        @interpreter = "powershell"
        @parameters = {}
        @source = nil
        @source_path = nil
        @action = :run
        @allowed_actions.push(:run)
      end

      # (String) Powershell nickname
      def nickname(arg=nil)
        set_or_return(
          :nickname,
          arg,
          :kind_of => [ String ]
        )
      end

      # (String) text of Powershell source code if inline
      def source(arg=nil)
        set_or_return(
          :source,
          arg,
          :kind_of => [ String ]
        )
      end

      # (String) local path for external Powershell source file if not inline
      def source_path(arg=nil)
        set_or_return(
          :source_path,
          arg,
          :kind_of => [ String ]
        )
      end

      # (Hash) Powershell parameters values keyed by names
      def parameters(arg=nil)
        return environment if arg.nil?

        # FIX: support Windows alpha demo-style parameters for now. document
        # that they are deprecated and to use a simple hash. this method of
        # parameter passing may be deprecated altogether in future.
        if arg.kind_of?(Chef::Node::Attribute)
          arg = arg.attribute
        end

        # parameters is really a duplication of the environment hash from
        # the ExecuteResource, so merge the two hashes, if necessary. it seems
        # valid to continue to distinguish symantically between parameters and
        # environment because the user does not necessarily need to know that
        # they are implemented to be the same hash.
        env = environment
        if env.nil?
          env = arg
        else
          env.merge!(arg)
        end
        environment(env)
        @parameters = @environment
      end

    end
  end
end
