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

      # Runs a Chef recipe.
      #
      # === Parameters
      # cookbook_path(String):: path to cookbook containing recipes in run_list.
      # 
      # run_list(String or Array):: fully-qualified recipe name(s) including cookbook name.
      #
      # === Returns
      # true always
      #
      # === Raises
      # RightScale::Exceptions::Exec on failure
      def run_chef(cookbook_path, run_list)
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

        EM.threadpool_size = 1
        EM.run do
          EM.defer do
            begin
              chef_client.run_solo
            rescue Exception => e
              # can't raise exeception out of EM, so cache it here.
              last_exception = e
            end
            done = true
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

      module_function :run_chef

    end
  end
end
