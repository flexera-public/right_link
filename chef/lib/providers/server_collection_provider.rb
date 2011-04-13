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

  class Provider

    # ServerCollection chef provider.
    # Allows retrieving a set of servers by tags
    class ServerCollection < Chef::Provider

      # Maximum number of seconds to wait for tags query results
      QUERY_TIMEOUT = 60

      # Initialize condition variable used to synchronize chef and EM threads
      def initialize(node, resource, collection=nil, definitions={}, cookbook_loader=nil)
        super(node, resource)
        @mutex        = Mutex.new
        @loaded_event = ConditionVariable.new
      end

      # This provider doesn't actually change any state on the server
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Get the tagged servers *synchronously*
      #
      # === Return
      # true:: Always return true
      def action_load
        node[:server_collection] ||= {}
        node[:server_collection][@new_resource.name] = {}
        return unless @new_resource.tags && !@new_resource.tags.empty?
        status = :pending
        result = nil
        @mutex.synchronize do
          EM.next_tick do
            # Create the timer in the EM Thread
            @timeout_timer = EM::Timer.new(QUERY_TIMEOUT) do
              @mutex.synchronize do
                status = :failed
                @loaded_event.signal
              end
            end
          end
          payload = {:agent_ids => @new_resource.agent_ids, :tags => @new_resource.tags}
          RightScale::Cook.instance.send_retryable_request("/mapper/query_tags", payload) do |r|
            res = RightScale::OperationResult.from_results(r)
            if res.success?
              @mutex.synchronize do
                if status == :pending
                  result = res.content
                  status = :succeeded
                  @timeout_timer.cancel
                  @timeout_timer = nil
                  @loaded_event.signal
                end
              end
            else
              RightScale::RightLinkLog.error("Failed to get tagged servers, got: #{res.content}")
            end
          end
          @loaded_event.wait(@mutex)
        end
        if status == :succeeded && result
          collection = result.inject({}) { |res, (k, v)| res[k] = v['tags']; res }
          node[:server_collection][@new_resource.name] = collection
        else
          RightScale::RightLinkLog.debug("ServerCollection load failed for #{@new_resource.name} (timed out after #{QUERY_TIMEOUT}s)")
        end
        true
      end

    end # ServerCollection

  end # Provider

end # Chef

# self-register
Chef::Platform.platforms[:default].merge!(:server_collection => Chef::Provider::ServerCollection)
