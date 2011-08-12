#
# Copyright (c) 2009-2011 RightScale Inc
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

    # RightLinkTag chef provider.
    class RightLinkTag < Chef::Provider

      # Load current
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Publish tag
      #
      # === Return
      # true:: Always return true
      def action_publish
        RightScale::Cook.instance.add_tag(@new_resource.name)
        true
      end

      # Remove tag
      #
      # === Return
      # true:: Always return true
      def action_remove
        RightScale::Cook.instance.remove_tag(@new_resource.name)
        true
      end

    end

  end

end

# self-register
Chef::Platform.platforms[:default].merge!(:right_link_tag => Chef::Provider::RightLinkTag)
