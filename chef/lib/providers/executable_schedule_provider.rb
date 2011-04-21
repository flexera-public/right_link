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

      # Initialize underlying Chef cron provider with existing entries
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        @original_cron_provider = Chef::Provider::Cron.new(@new_resource.cron_resource, @run_context)
        @original_cron_provider.load_current_resource
        @current_resource = @original_cron_provider.current_resource
        true
      end

      # Create cron entries if they don't exist yet
      #
      # === Return
      # true:: Always return true
      def action_create
        @original_cron_provider.action_create
        @new_resource.updated_by_last_action(@original_cron_provider.new_resource.updated_by_last_action?)
        true
      end

      # Delete existing cron entries, do nothing if they don't exist
      #
      # === Return
      # true:: Always return true
      def action_delete
        @original_cron_provider.action_delete
        @new_resource.updated_by_last_action(@original_cron_provider.new_resource.updated_by_last_action?)
      end

    end

  end
end

# self-register
Chef::Platform.platforms[:default].merge!(:executable_schedule => Chef::Provider::ExecutableSchedule)
