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

class Chef
  class Resource

    # Recipe that should be run on a remote RightLink agent
    #
    class RemoteRecipe < Chef::Resource

      # Initialize log resource with a name as the string to log
      #
      # === Parameters
      # name(String):: Message to log
      # collection(Array):: Collection of included recipes
      # node(Chef::Node):: Node where resource will be used
      def initialize(name, run_context=nil)
        super(name, run_context)
        @resource_name = :remote_recipe
        @scope = :all
        @action = :run
        @allowed_actions.push(:run)
      end

      # Name of recipe that should be run remotely
      def recipe(arg=nil)
        set_or_return(
          :recipe,
          arg,
          :kind_of => [ String ]
        )
      end

      # Override attributes that should be used to run the remote recipe
      def attributes(arg=nil)
        set_or_return(
          :attributes,
          arg,
          :kind_of => [ Hash ]
        )
      end

      # List of ids of agents that should run the recipe
      # These ids should have been retrieved using the :from attribute
      # of a remote recipe previously run on this agent
      def recipients(arg=nil)
        converted_arg = arg.is_a?(String) ? [ arg ] : arg
        set_or_return(
          :recipients,
          converted_arg,
          :kind_of => [ Array ]
        )
      end

      # List of tags used to route the request
      # Only instances that expose *all* of the tags in this list
      # will run the recipe
      def recipients_tags(arg=nil)
        converted_arg = arg.is_a?(String) ? [ arg ] : arg
        set_or_return(
          :recipient_tags,
          converted_arg,
          :kind_of => [ Array ]
        )
      end

      # Scope of remote recipe: whether a single or all potential recipients
      # should run the recipe.
      # Only applies when used in conjunction with +recipients_tags+
      # Defaults to :all
      def scope(arg=nil)
        set_or_return(
          :scope,
          arg,
          :equal_to => [ :single, :all ]
        )
      end
    end
  end
end


