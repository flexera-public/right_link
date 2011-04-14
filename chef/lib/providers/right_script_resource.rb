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

# To install the chef gem:
# sudo gem sources -a http://gems.opscode.com
# sudo gem install chef ohai

require 'fileutils'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'right_link_config'))

class Chef

  class Resource

    # RightScript chef resource.
    # Allows defining recipes which wrap RightScripts.
    #
    # === Example
    # right_script "APP Mephisto bootstrap configure v2" do
    #   source_file '/tmp/my_right_script'
    #   parameters['APPLICATION'] 'My Mephisto App'
    #   parameters['DB_SCHEMA_NAME'] 'db_schema'
    #   parameters['RAILS_ENV'] 'production'
    #   cache_dir '/var/cache/rightscale/app_mephisto'
    # end
    class RightScript < Chef::Resource

      # Default directory used to cache RightScript source
      DEFAULT_CACHE_DIR_ROOT = ::File.join(RightScale::RightLinkConfig.platform.filesystem.cache_dir, 'rightscale')

      # Initialize RightScript resource with default values
      #
      # === Parameters
      # name(String):: Nickname of RightScript
      # collection(Array):: Collection of included recipes
      # node(Chef::Node):: Node where resource will be used
      def initialize(name, run_context=nil)
        super(name, run_context)
        @resource_name = :right_script
        @cache_dir = ::File.join(DEFAULT_CACHE_DIR_ROOT, RightScale::AgentIdentity.generate)
        @parameters = {}
        @action = :run
        @allowed_actions.push(:run)
      end

      # (String) RightScript nickname
      def nickname(arg=nil)
        set_or_return(
          :nickname,
          arg,
          :kind_of => [ String ]
        )
      end

      # (String) Path to file containing RightScript source code
      def source_file(arg=nil)
        set_or_return(
          :source_file,
          arg,
          :kind_of => [ String ]
        )
      end

      # (Hash) RightScript parameters values keyed by names
      def parameters(arg=nil)
        set_or_return(
          :parameters,
          arg,
          :kind_of => [ Hash ]
        )
      end

      # (String) Path to directory where attachments source should be saved
      def cache_dir(arg=nil)
        set_or_return(
          :cache_dir,
          arg,
          :kind_of => [ String ]
        )
      end

    end
  end
end
