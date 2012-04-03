# Copyright (c) 2009-2011 RightScale Inc
#
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

      # Initialize condition variable used to synchronize chef and EM threads
      def initialize(node, resource, collection=nil, definitions={}, cookbook_loader=nil)
        super(node, resource)
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

        result = RightScale::Cook.instance.query_tags(@new_resource.tags, @new_resource.agent_ids, @new_resource.timeout)
        collection = result.inject({}) { |res, (k, v)| res[k] = v['tags']; res }
        node[:server_collection][@new_resource.name] = collection
        true
      end

    end # ServerCollection

  end # Provider

end # Chef

# self-register
Chef::Platform.platforms[:default].merge!(:server_collection => Chef::Provider::ServerCollection)
