#
# Copyright (c) 2010-2013 RightScale Inc
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

module RightScale
  module Test
    module ChefRunner

      class MockSystemExit < Exception; end

      extend self

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

      # Creates a cookbook from a hash of recipe names to text.
      #
      # === Parameters
      # base_path(String):: path to base cookbooks directory.
      # recipes(Hash):: hash of recipe names to text.
      # cookbook_name(String):: name of cookbook (defaults to 'test').
      # data_files(Hash):: hash of data file names to file text or empty or nil.
      #
      # === Returns
      # cookbooks_path(String):: path to created cookbooks directory
      def create_cookbook(base_path, recipes, cookbook_name = 'test', data_files = nil)
        cookbooks_path = get_cookbooks_path(base_path)
        ::FileUtils.mkdir_p(cookbooks_path)
        cookbook_path = ::File.normalize_path(cookbook_name, cookbooks_path)
        recipes_path = ::File.join(cookbook_path, 'recipes')
        ::FileUtils.mkdir_p(recipes_path)
        metadata_text =
<<EOF
maintainer "RightScale, Inc."
version    "0.1"
EOF
        recipes.each do |key, value|
          recipe_name = key.to_s
          recipe_text = value
          recipe_path = File.join(recipes_path, recipe_name + ".rb")
          File.open(recipe_path, "w") { |f| f.write(recipe_text) }
          metadata_text += "recipe     \"#{cookbook_name}::#{recipe_name}\", \"Description of #{recipe_name}\"\n"
        end

        if data_files
          data_files_path = File.join(cookbook_path, 'data')
          FileUtils.mkdir_p(data_files_path)
          data_files.each do |key, value|
            data_file_name = key.to_s
            data_file_text = value
            data_file_path = File.join(data_files_path, data_file_name)
            File.open(data_file_path, "w") { |f| f.write(data_file_text) }
          end
        end

        # metadata
        metadata_path = recipes_path = File.join(cookbook_path, 'metadata.rb')
        File.open(metadata_path, "w") { |f| f.write(metadata_text) }

        # rake metadata
        md = Chef::Cookbook::Metadata.new
        md.name(cookbook_name)
        md.from_file(metadata_path)
        json_file = File.join(cookbook_path, 'metadata.json')
        File.open(json_file, "w") do |f|
          f.write(Chef::JSONCompat.to_json_pretty(md))
        end

        # done
        return cookbooks_path
      end

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

      # @return [String] backup path for chef tests that do backups
      def backup_path
        ::File.join(::Dir.tmpdir, 'chef_runner_file_backup_path-b2ce23dbae2c2cd186519c7cf7e9c7e5')
      end

      protected

      TEMP_DIR_NAME = "chef-runner-FF628CD5-9D48-46ff-BC11-D9DE3CC2215A"

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
        # ensure local drive for cookbook because scripts cannot run from
        # network locations (in windows).
        platform = RightScale::Platform
        cookbook_path = platform.filesystem.ensure_local_drive_path(cookbook_path, TEMP_DIR_NAME)
        unless ::File.directory?(cookbook_path)
          raise ArgumentError, "Missing cookbook directory: #{cookbook_path.inspect}"
        end

        # minimal chef configuration.
        ::Chef::Config[:solo] = true
        ::Chef::Config[:cookbook_path] = cookbook_path

        # setup logger for mixlib-shellout gem to consume instead of the chef
        # v0.10.10 behavior of not logging ShellOut calls by default. also setup
        # command failure exception and callback for legacy reasons.
        ::Mixlib::ShellOut.default_logger = Chef::Log
        ::Mixlib::ShellOut.command_failure_callback = lambda do |params|
          failure_reason = ::RightScale::SubprocessFormatting.reason(params[:status])
          expected_error_codes = Array(params[:args][:returns]).join(' or ')
          ::RightScale::Exceptions::Exec.new("\"#{params[:args][:command]}\" #{failure_reason}, expected #{expected_error_codes}.",
                                             params[:args][:cwd])
        end

        # must set file cache path and ensure it exists otherwise evented run_command will fail
        cache_dir_path = File.join(::RightScale::Platform.filesystem.temp_dir, 'chef_runner_1B0C7CAA87E241daB90B75829DD6A833')
        AgentConfig.cache_dir = cache_dir_path
        file_cache_path = File.join(AgentConfig.cache_dir, 'chef')
        ::Chef::Config[:file_cache_path] = file_cache_path
        ::Ohai::Config[:hints_path] = [ File.join(AgentConfig.cache_dir, "ohai", "hints") ]
        ::Chef::Config[:cache_options][:path] = File.join(file_cache_path, 'checksums')
        ::Chef::Config[:client_fork] = false
        FileUtils.rm_rf(::Chef::Config[:file_cache_path])
        FileUtils.mkdir_p(::Chef::Config[:file_cache_path])
        FileUtils.mkdir_p(::Chef::Config[:cache_options][:path])

        # specify a backup path for tests that backup files only because we
        # sometimes run specs from a network drive and the default backup path
        # is the empty root (/), which works great on Linux but not on Windows.
        ::Chef::Config[:file_backup_path] = backup_path

        # prepare to run solo chef.
        run_list = [ run_list ] unless run_list.kind_of?(Array)
        attribs = { 'recipes' => run_list }
        chef_client = ::Chef::Client.new(attribs)
        done = false
        chef_node_server_terminated = false
        last_exception = nil

        # suppress unnecessary error log output for cases of explictly exiting
        # from converge (rs_shutdown, etc.).
        ::Chef::Client.clear_notifications

        powershell_providers = nil
        if platform.windows?
          # generate the powershell providers if any in the cookbook
          dynamic_provider = DynamicPowershellProvider.new
          dynamic_provider.generate_providers(Chef::Config[:cookbook_path])
          powershell_providers = dynamic_provider.providers
        end

        EM.threadpool_size = 1
        EM.run do
          EM.defer do
            begin
              chef_client.run
              block.call(chef_client) if block
            rescue SystemExit => e
              # can't raise exit out of EM, so cache it here.
              last_exception = e
            rescue Exception => e
              # can't raise exeception out of EM, so cache it here.
              last_exception = e
            ensure
              # terminate the powershell providers
              Chef::Log.debug("***************************** TERMINIATING PROVIDERS *****************************")

              # terminiate the providers before the node server as the provider term scripts may still use the node server
              if powershell_providers
                powershell_providers.each do |p|
                  begin
                    p.terminate
                  rescue Exception => e
                    Chef::Log.debug(Log.format("Error terminating '#{p.inspect}'", e, :trace))
                  end
                end
              end
              Chef::Log.debug("***************************** PROVIDERS TERMINATED *****************************")
            end

            if run_as_server
              puts "Hit Ctrl+C to cancel Chef server."
            else
              done = true
            end
          end
          timer = EM::PeriodicTimer.new(0.1) do
            if done
              if chef_node_server_terminated
                timer.cancel
                EM.stop
              else
                # kill the chef node provider
                RightScale::Windows::ChefNodeServer.instance.stop rescue nil if RightScale::Platform.windows?
                chef_node_server_terminated = true
              end
            end
          end
        end

        # remove temporary cookbook directory, if necessary.
        Dir.chdir(platform.filesystem.temp_dir) do
          (FileUtils.rm_rf(TEMP_DIR_NAME) rescue nil) if ::File.directory?(TEMP_DIR_NAME)
        end

        # reraise with full backtrace for debugging purposes. this assumes the
        # exception class accepts a single string on construction.
        if last_exception
          message = "#{last_exception.message}\n#{last_exception.backtrace.join("\n")}"
          if last_exception.class == ArgumentError
            raise ArgumentError, message
          elsif last_exception.class == SystemExit
            raise MockSystemExit.new("SystemExit(#{last_exception.status}): #{message}")
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
    end
  end
end
