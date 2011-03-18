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

# To install the chef gem:
# sudo gem sources -a http://gems.opscode.com
# sudo gem install chef ohai

require 'fileutils'

class Chef

  class Resource

    # ExecutableSchedule chef resource.
    # Allows defining the schedule(cron) for a right script or a recipe
    class ExecutableSchedule < Chef::Resource

      # Initialize ExecutableSchedule resource with default values
      #
      # === Parameters
      # name(String):: Name of the schedule
      def initialize(name, run_context=nil)
        super(name, run_context)
        @cron_resource = Chef::Resource::Cron.new(name)
        @cron_resource.user('rightscale')
        @resource_name = :executable_schedule
        recipe nil
        recipe_id nil
        right_script nil
        right_script_id nil
        @action = :create
        @allowed_actions.push(:create, :delete)
      end

      # (Chef::Resource::Cron) Underlying cron resource
      attr_accessor :cron_resource
      
      # (String) Schedule name
      def name(arg=nil)
        @cron_resource.name(arg)
      end

      # (String) Schedule minute
      def minute(arg=nil)
        @cron_resource.minute(arg)
      end

      # (String) Schedule hour
      def hour(arg=nil)
        @cron_resource.hour(arg)
      end

      # (String) Schedule day
      def day(arg=nil)
        @cron_resource.day(arg)
      end

      # (String) Schedule month
      def month(arg=nil)
        @cron_resource.month(arg)
      end

      # (String) Schedule weekday
      def weekday(arg=nil)
        @cron_resource.weekday(arg)
      end

      # (String) recipe name for the schedule
      def recipe(arg=nil)
        set_or_return(
          :recipe,
          arg,
          :kind_of => [ String ]
        )

        @cron_resource.command "rs_run_recipe -n #{arg}" if arg
      end

      # (String) recipe id for the schedule
      def recipe_id(arg=nil)
        if Integer(arg) < 0 then raise RangeError end
        if arg.is_a?(Integer)
          converted_arg = arg.to_s
        else
          converted_arg = arg
        end
        set_or_return(
          :recipe_id,
          converted_arg,
          :kind_of => [ String ]
        )

        @cron_resource.command "rs_run_recipe -i #{converted_arg}" if arg
      end

      # (String) RightScript's name for the schedule
      def right_script(arg=nil)
        set_or_return(
          :right_script,
          arg,
          :kind_of => [ String ]
        )

        @cron_resource.command "rs_run_right_script -n #{arg}" if arg
      end

      # (String) RightScript's id for the schedule
      def right_script_id(arg=nil)
        if Integer(arg) < 0 then raise RangeError end
        if arg.is_a?(Integer)
          converted_arg = arg.to_s
        else
          converted_arg = arg
        end
        set_or_return(
          :right_script_id,
          converted_arg,
          :kind_of => [ String ]
        )

        @cron_resource.command "rs_run_right_script -i #{converted_arg}" if arg
      end
    end
  end
end
