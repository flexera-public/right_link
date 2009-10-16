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
  class Provider

    # Executable Schedule chef provider.
    class ExecutableSchedule < Chef::Provider

      def load_current_resource
        @current_resource = Chef::Resource::ExecutableSchedule.new("")

        #TODO: Currently, we are using the cron provider from chef 0.7.12. Update the following code when we upgrade chef.
        @original_cron_provider = Chef::Provider::Cronv0_7_12.new(@node, @new_resource.cron_resource)
        @current_resource.cron_resource = @original_cron_provider.load_current_resource
        @current_resource
      end

      def action_create
        raise Chef::Exceptions::ExecutableSchedule::ScheduleAlreadyExists, "The schedule named #{@new_resource.name} already exists." if cron_exists
        @original_cron_provider.action_create
        @new_resource.updated = @original_cron_provider.new_resource.updated
      end

      def action_update
        raise Chef::Exceptions::ExecutableSchedule::ScheduleNotFound, "The schedule named #{@new_resource.name} does not exist." if !cron_exists
        @original_cron_provider.action_create
        @new_resource.updated = @original_cron_provider.new_resource.updated
      end

      def action_delete
        raise Chef::Exceptions::ExecutableSchedule::ScheduleNotFound, "The schedule named #{@new_resource.name} does not exist." if !cron_exists
        @original_cron_provider.action_delete
        @new_resource.updated = @original_cron_provider.new_resource.updated
      end

      private
      def cron_exists
        @original_cron_provider.cron_exists
      end

      def cron_empty
        @original_cron_provider.cron_empty
      end
    end

  end

end