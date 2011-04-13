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
    class DnsMadeEasy < Chef::Provider 

      # No concept of a 'current' resource for DNS registration, this is a no-op
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Register DNS with DNS Made Easy service
      # This relies on 'curl' being available on the system
      #
      # === Return
      # true:: Always return true
      #
      # === Raise
      # Chef::Exceptions::Dns:: DNS registration request returned an error
      def action_register
        Chef::Log.info("Updating DNS for #{@new_resource.name} to point to #{@new_resource.ip_address}")
        query="username=#{@new_resource.user}&password=#{@new_resource.passwd}&id=#{@new_resource.name}&ip=#{@new_resource.ip_address}"
        Chef::Log.debug("QUERY: #{query}")
        result = post_change(query)
        if result =~ /success|error-record-ip-same/
          Chef::Log.info("DNSID #{@new_resource.name} set to this instance IP: #{@new_resource.ip_address}")
        else
          raise(Chef::Exceptions::Dns, "#{self.class.name}: Error setting #{@new_resource.name} to instance IP: #{@new_resource.ip_address}: Result: #{result}")
        end
        true
      end
      
      # Make the HTTPS request using 'curl'
      #
      # === Parameters
      # query(String):: Query string used to build request
      #
      # === Return
      # res(String):: Response content
      def post_change(query)
        # use double-quotes for Window but use single-quotes for security
        # reasons in Linux.
        curl_options = '-S -s --retry 7 -k -o - -g -f'
        dns_made_easy_url = 'https://www.dnsmadeeasy.com/servlet/updateip'
        if !!(RUBY_PLATFORM =~ /mswin/)
          res = `curl #{curl_options} \"#{dns_made_easy_url}?#{query}\"`
        else
          res = `curl #{curl_options} '#{dns_made_easy_url}?#{query}'`
        end
        return res
      end
      
    end
  end
end

# self-register
Chef::Platform.platforms[:default].merge!(:dns => Chef::Provider::DnsMadeEasy)
