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

    
## Set DNS for given id to the current address of this node
#
#dns "my.domain.id.com" do
#  user "account_user_name"
#  passwd "account_password"
#  addressing :public | :private (:public default)
#end

class Chef
  class Resource
    
    # RightScript chef resource.
    # Set DNS for given id to the current address of this node
    #
    # === Example
    #dns "my.domain.id.com" do
    #  user "account_user_name"
    #  passwd "account_password"
    #  ip_address "nnn.nnn.nnn.nnn"
    #end
    #
    class Dns < Chef::Resource
      
      # Initialize DNS resource with default values
      #
      # === Parameters
      # name(String):: FQDN or Id for server
      # collection(Array):: Collection of included recipes
      # node(Chef::Node):: Node where resource will be used
      def initialize(name, run_context=nil)
        super(name, run_context)
        @resource_name = :dns
        @dns_id = nil
        @user = nil
        @passwd = nil
        @ip_address = nil
        @action = :register        
      end
      
      # (String) username for dns provider account
      def user(arg=nil)
        set_or_return(
          :user,
          arg,
          :kind_of => [ String ]
        )
      end

      # (String) password for dns provider account      
      def passwd(arg=nil)
        set_or_return(
          :passwd,
          arg,
          :kind_of => [ String ]
        )
      end
      
      # (String) IP address in the format ddd.ddd.ddd.ddd 
      def ip_address(arg=nil)
        set_or_return(
          :ip_address,
          arg,
          :regex => /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/
        )
      end

    end
  end  
end

# Define the Dns exception type
class Chef
  class Exceptions
    class Dns < RuntimeError; end
  end
end

