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
    class WindowsUnsupported < Chef::Provider::Execute

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
Chef::Platform.platforms[:windows][:default].merge!(:link => Chef::Provider::WindowsUnsupported,      # not yet implemented. NTFS supports hard & symbolic links.
                                                    :mount => Chef::Provider::WindowsUnsupported,     # not yet implemented. NTFS supports mount points.
                                                    :service => Chef::Provider::WindowsUnsupported,   # not yet implemented. 'net' commands are used to start/stop services.
                                                    :bash => Chef::Provider::WindowsUnsupported,      # we don't intend to support Linux
                                                    :csh => Chef::Provider::WindowsUnsupported,       #  shells under Windows.
                                                    :user => Chef::Provider::WindowsUnsupported,      # not yet implemented. need a custom provider.
                                                    :group => Chef::Provider::WindowsUnsupported,     # not yet implemented. need a custom provider.
                                                    :route => Chef::Provider::WindowsUnsupported,     # not yet implemented. WMI supports DNS configuration.
                                                    :ifconfig => Chef::Provider::WindowsUnsupported)  # not yet implemented. WMI supports DNS configuration.
