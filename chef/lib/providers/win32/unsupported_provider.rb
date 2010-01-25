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

class Chef
  class Provider
    class Win32Unsupported < Chef::Provider::Execute

      class UnsupportedException < StandardError
        def initialize(resource)
          message = "The \"#{resource.resource_name}\" resource referenced in recipe \"#{resource.cookbook_name}::#{resource.recipe_name}\" is not supported on Windows."
          super(message)
        end
      end

      def action_run
        raise(UnsupportedException, @new_resource)
      end

    end
  end
end

# self-register
Chef::Platform.platforms[:windows][:default].merge!(:mount => Chef::Provider::Win32Unsupported,     # NTFS supports mount points, but that doesn't mean we will.
                                                    :service => Chef::Provider::Win32Unsupported,   # not yet implemented.
                                                    :bash => Chef::Provider::Win32Unsupported,      # we don't intend to support Linux
                                                    :csh => Chef::Provider::Win32Unsupported,       #  shells under Windows.
                                                    :user => Chef::Provider::Win32Unsupported,      # not yet implemented.
                                                    :group => Chef::Provider::Win32Unsupported,     # not yet implemented.
                                                    :route => Chef::Provider::Win32Unsupported,     # not yet implemented.
                                                    :ifconfig => Chef::Provider::Win32Unsupported)  # not yet implemented.
