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

require 'chef/client'

# monkey patch to reduce how often sluggish ohai is invoked during spec test.
# we don't need realtime info, so static info should be good enough for testing.
class Chef
  class Client
    @@last_ohai = nil
    @@old_run_ohai = instance_method(:run_ohai)
    
    def run_ohai
      if @@last_ohai
        @ohai = @@last_ohai
      else
        @@old_run_ohai.bind(self).call
        @@last_ohai = @ohai
      end
    end
  end
end

module RightScale
  module Test
    module ChefRunner
      
      # Generates the path for the cookbooks directory for a given base path.
      #
      # === Parameters
      # base_path(String):: path to base cookbooks directory.
      #
      # === Returns
      # cookbooks_path(String):: path to created cookbooks directory
      def get_cookbooks_path(base_path)
        # Chef fails if cookbook paths contain backslashes.
        return File.join(base_path, "cookbooks").gsub("\\", "/")
      end
      
      module_function :get_cookbooks_path
      
      # Creates a cookbook from a hash of recipe names to text.
      #
      # === Parameters
      # base_path(String):: path to base cookbooks directory.
      # recipes(Hash):: hash of recipe names to text.
      # cookbook_name(String):: name of cookbook (defaults to 'test')
      #
      # === Returns
      # cookbooks_path(String):: path to created cookbooks directory
      def create_cookbook(base_path, recipes, cookbook_name = 'test')
        cookbooks_path = get_cookbooks_path(base_path)
        cookbook_path = File.join(cookbooks_path, cookbook_name)
        recipes_path = File.join(cookbook_path, 'recipes')
        FileUtils.mkdir_p(recipes_path)
        metadata_text =
<<EOF
maintainer "RightScale, Inc."
version    "0.1"
EOF
        recipes.keys.each do |key|
          recipe_name = key.to_s
          recipe_text = recipes[key]
          recipe_path = File.join(recipes_path, recipe_name + ".rb")
          File.open(recipe_path, "w") { |f| f.write(recipe_text) }
          metadata_text += "recipe     \"#{cookbook_name}\"::#{recipe_name}, \"Description of #{recipe_name}\"\n"
        end
        
        # metadata
        metadata_path = recipes_path = File.join(cookbook_path, 'metadata.rb')
        File.open(metadata_path, "w") { |f| f.write(metadata_text) }
        
        return cookbooks_path
      end
      
      module_function :create_cookbook
      
      # Runs a Chef recipe.
      #
      # === Parameters
      # cookbook_path(String):: path to cookbook containing recipes in run_list.
      #
      # run_list(String or Array):: fully-qualified recipe name(s) including cookbook name.
      #
      # block(Proc):: block to run after starting Chef or nil.
      #
      # === Returns
      # true always
      #
      # === Raises
      # RightScale::Exceptions::Exec on failure
      def run_chef(cookbook_path, run_list, &block)
        inner_run_chef(cookbook_path, run_list, false, &block)
      end
      
      module_function :run_chef
      
      # Runs a Chef recipe.
      #
      # === Parameters
      # cookbook_path(String):: path to cookbook containing recipes in run_list.
      #
      # run_list(String or Array):: fully-qualified recipe name(s) including cookbook name.
      #
      # block(Proc):: block to run after starting Chef or nil.
      #
      # === Returns
      # true always
      #
      # === Raises
      # RightScale::Exceptions::Exec on failure
      def run_chef_as_server(cookbook_path, run_list, &block)
        inner_run_chef(cookbook_path, run_list, true, &block)
      end
      
      module_function :run_chef_as_server
      
      protected
      
      # Runs a Chef recipe.
      #
      # === Parameters
      # cookbook_path(String):: path to cookbook containing recipes in run_list.
      #
      # run_list(String or Array):: fully-qualified recipe name(s) including cookbook name.
      #
      # run_as_server(Boolean):: true if Chef eventmachine will remain running
      # until cancelled (by Ctrl+C), false to stop eventmachine after running
      #
      # block(Proc):: block to run after starting Chef or nil.
      #
      # === Returns
      # true always
      #
      # === Raises
      # RightScale::Exceptions::Exec on failure
      def inner_run_chef(cookbook_path, run_list, run_as_server, &block)
        # minimal chef configuration.
        ::Chef::Config[:solo] = true
        ::Chef::Config[:cookbook_path] = cookbook_path

        # must set file cache path for Windows case of using remote files, templates. etc.
        platform = RightScale::RightLinkConfig[:platform]
        Chef::Config[:file_cache_path] = File.join(platform.filesystem.cache_dir, 'chef') if platform.windows?

        # prepare to run solo chef.
        run_list = [ run_list ] unless run_list.kind_of?(Array)
        attribs = { 'recipes' => run_list }
        chef_client = ::Chef::Client.new
        chef_client.json_attribs = attribs
        done = false
        last_exception = nil

        powershell_providers = nil
        if platform.windows?
          # generate the powershell providers if any in the cookbook
          dynamic_provider = DynamicPowershellProvider.new
          dynamic_provider.generate_providers(Chef::Config[:cookbook_path])
          powershell_providers = dynamic_provider.providers
        end

        if run_as_server
          puts "Hit Ctrl+C to cancel Chef server."
        end
        EM.threadpool_size = 1
        EM.run do
          EM.defer do
            begin
              chef_client.run_solo
              block.call(chef_client) if block
            rescue Exception => e
              # can't raise exeception out of EM, so cache it here.
              last_exception = e
            ensure
              # terminate the powershell providers
              Chef::Log.debug("*****************************")
              (powershell_providers || []).each do |p|
                begin
                  Chef::Log.debug("TERMINATING #{p.inspect}")
                  p.terminate
                  Chef::Log.debug("*****************************")
                rescue Exception => e
                  Chef::Log.debug("*****************************\nKABOOM #{e.message + "\n" + e.backtrace.join("\n")}\n*****************************")
                  last_exception = e
                end
              end
            end
            Chef::Log.debug("*****************************\nSETTING DONE TO #{!run_as_server}\n*****************************")
            done = (not run_as_server)
          end
          timer = EM::PeriodicTimer.new(0.1) do
            if done
              timer.cancel
              EM.stop
            end
          end
        end

        # reraise with full backtrace for debugging purposes. this assumes the
        # exception class accepts a single string on construction.
        if last_exception
          message = "#{last_exception.message}\n#{last_exception.backtrace.join("\n")}"
          if last_exception.class == ArgumentError
            raise ArgumentError, message
          else
            begin
              raise last_exception.class, message
            rescue ArgumentError
              # exception class does not support single string construction.
              message = "#{last_exception.class}: #{message}"
              raise message
            end
          end
        end
        true
      end
      
      module_function :inner_run_chef
      
    end
  end
end
