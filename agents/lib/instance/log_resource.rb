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

    
## Writes a string to the chef log from a recipe
#
#log "some string to log" do
#  level :info  #(default)  :warn, :debug, :error, :fatal also supported.
#end

class Chef
  class Resource
    
    # Sends a string from a recipe to the chef log object
    #
    # === Example
    #log "your string to log" 
    #
    # or 
    #
    #log "a debug string" { level :debug }
    #  
    class Log < Chef::Resource
      
      # Initialize log resource with a name as the string to log 
      def initialize(name, collection=nil, node=nil)
        super(name, collection, node)
        @resource_name = :log
        @level = :info
        @action = :write
      end
      
      # what level do you want to log at?
      def level(arg=nil)
        set_or_return(
          :level,
          arg,
          :equal_to => [ :debug, :info, :warn, :error, :fatal ]
        )
      end
      
    end
  end  
end

class Chef 
  class Provider
    class Log < Chef::Provider 
            
      def load_current_resource
        true
      end
      
      def write
        Chef::Log.send(@new_resource.level, @new_resource.name)
      end
    end
  end
end

class Chef
  class Platform
    @platforms ||= {}
  end
end 
Chef::Platform.platforms[:default].merge! :log => Chef::Provider::Log

class Chef
  class Exceptions
    class Log < RuntimeError; end
  end
end

