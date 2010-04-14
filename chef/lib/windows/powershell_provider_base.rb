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

module RightScale

  # Base class to dynamically generated Powershell Chef providers
  class PowershellProviderBase < Chef::Provider
    def initialize(node, new_resource, collection=nil, definitions=nil, cookbook_loader=nil)
      super(node, new_resource, collection, definitions, cookbook_loader)
      self.class.init
      # Have to wait until the Chef node server has been initialized before setting the new resource
      RightScale::Windows::ChefNodeServer.instance.new_resource = new_resource
    end

    # Initialize Powershell host, should be called before :run and :terminate
    #
    # === Return
    # true:: If init script must be run
    # false:: Otherwise
    def self.init
      run_init = @ps_instance.nil?
      @ps_instance = PowershellHost.new(:node => @node, :provider_name => self.to_s.gsub("::","_") ) unless @ps_instance
      run_init      
    end

    # Run powershell script in associated Powershell instance
    #
    # === Parameters
    # script(String):: Fully qualified path to Powershell script
    #
    # === Return
    # true:: Always return true
    def self.run_script(script)
      if @ps_instance
        if @ps_instance.active
          @ps_instance.run(script)
        else
          RightLinkLog.error("Powershell provider #{self} could not run Powershell script #{script} because the Powershell host is not active")
        end
      end
      true
    end

    # Terminate Powershell process if it was started
    #
    # === Return
    # true:: Always return true
    def self.terminate
      if @ps_instance
        @ps_instance.terminate
        @ps_instance = nil
      end
      true
    end

    # Must override Chef's load_current_resource
    #
    # === Return
    # true:: Always return true
    def load_current_resource
      # Dummy
    end
  end

end