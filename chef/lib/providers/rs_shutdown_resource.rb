#
# Copyright (c) 2011 RightScale Inc
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

    # Scriptable system shutdown chef resource.
    class RsShutdown < Chef::Resource

      # Initialize rs_shutdown resource
      #
      # === Parameters
      # name(String):: Tag name
      # collection(Array):: Collection of included recipes
      # node(Chef::Node):: Node where resource will be used
      def initialize(name, collection=nil, node=nil)
        super(name, collection, node)
        @resource_name = :rs_shutdown
        @action = :reboot
        @immediately = false
        @allowed_actions.push(:reboot, :stop, :terminate)
      end

      # (String) RightScript nickname
      def immediately(arg=nil)
        set_or_return(
          :immediately,
          arg,
          :kind_of => [ TrueClass, FalseClass ]
        )
      end

    end

  end

end
