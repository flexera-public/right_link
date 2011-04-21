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

    # RemoteRecipe chef provider.
    class RemoteRecipe < Chef::Provider

      # No concept of a 'current' resource for RemoteRecipe execution, this is a no-op
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Actually run RemoteRecipe
      #
      # === Return
      # true:: Always return true
      def action_run
        tags          = @new_resource.recipients_tags
        recipients    = @new_resource.recipients
        agent_options = RightScale::OptionsBag.load
        attributes    = { :remote_recipe => { :tags => tags,
                                              :from => agent_options[:identity] } }
        attributes.merge!(@new_resource.attributes) if @new_resource.attributes
        payload = { :recipe => @new_resource.recipe, :json => attributes.to_json }
        if recipients && !recipients.empty?
          target = if (s = recipients.size) == 1
                     'one remote instance'
                   else
                     "#{s} remote instances"
                   end
          Chef::Log.info("Scheduling execution of #{@new_resource.recipe.inspect} on #{target}")
          recipients.each do |recipient|
            RightScale::Cook.instance.send_push('/instance_scheduler/execute', payload, recipient)
          end
        end
        if tags && !tags.empty?
          selector = (@new_resource.scope == :single ? :any : :all)
          target_tag = if tags.size == 1
                         "tag #{tags.first.inspect}"
                       else
                         "tags #{tags.map { |t| t.inspect }.join(', ') }"
                       end
          target = if selector == :all
                     "all instances with #{target_tag}"
                   else
                     "one instance with #{target_tag}"
                   end
          Chef::Log.info("Scheduling execution of #{@new_resource.recipe.inspect} on #{target}")
          RightScale::Cook.instance.send_push('/instance_scheduler/execute', payload, {:tags => tags, :selector => selector})
        end
        true
      end
 
    end

  end
 
end

# self-register
Chef::Platform.platforms[:default].merge!(:remote_recipe => Chef::Provider::RemoteRecipe)
