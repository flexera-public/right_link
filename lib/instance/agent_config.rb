#
# Copyright (c) 2009-2011 RightScale Inc
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

  # Extend AgentConfig for instance agents
  AgentConfig.module_eval do

    # Path to RightScale files at base of RightLink
    def self.parent_dir
      File.dirname(File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'right_link')))
    end

    # Path to directory containing persistent RightLink agent state
    def self.agent_state_dir
      RightScale::Platform.filesystem.right_scale_state_dir
    end

    # Path to directory containing transient cloud-related state (metadata, userdata, etc)
    def self.cloud_state_dir
      @cloud_state_dir ||= File.join(RightScale::Platform.filesystem.spool_dir, 'cloud')
    end

    # Set path to directory containing transient cloud-related state (metadata, userdata, etc)
    def self.cloud_state_dir=(dir)
      @cloud_state_dir = dir
    end

    # Path to directory for caching instance data
    def self.cache_dir
      @cache_dir ||= File.join(RightScale::Platform.filesystem.cache_dir, 'rightscale')
    end

    # Set path to directory for caching instance data
    def self.cache_dir=(dir)
      @cache_dir = dir
    end

    # Path to downloaded cookbooks directory
    def self.cookbook_download_dir
      @cookbook_download_dir ||= File.join(cache_dir, 'cookbooks')
    end

    # Path to RightScript recipes cookbook directory
    def self.right_scripts_repo_dir
      @right_scripts_repo_dir ||= File.join(cache_dir, 'right_scripts')
    end

    # Maximum number of times agent should retry installing packages
    def self.max_packages_install_retries
      3
    end

    # Path to directory for sandbox if it exists
    def self.sandbox_dir
      dir = RightScale::Platform.filesystem.sandbox_dir
      File.directory?(dir) ? dir : nil
    end

    # Sandbox ruby command
    def self.sandbox_ruby_cmd
      # Allow test environment to specify a non-program files location for tools
      if ENV['RS_RUBY_EXE']
        ENV['RS_RUBY_EXE']
      elsif RightScale::Platform.windows?
        if sandbox_dir
          RightScale::Platform.shell.sandbox_ruby
        else
          'ruby'
        end
      else
        if sandbox_dir && File.exist?(RightScale::Platform.shell.sandbox_ruby)
          RightScale::Platform.shell.sandbox_ruby
        else
          # Development setup
          `which ruby`.chomp
        end
      end
    end

    # Sandbox gem command
    def self.sandbox_gem_cmd
      if RightScale::Platform.windows?
        # Allow test environment to specify a non-program files location for tools
        if ENV['RS_GEM']
          ENV['RS_GEM']
        elsif dir = sandbox_dir
          "\"#{sandbox_ruby_cmd}\" \"#{File.join(dir, 'Ruby', 'bin', 'gem.exe')}\""
        else
          'gem'
        end
      else
        if dir = sandbox_dir
          File.join(dir, 'bin', 'gem')
        else
          # Development setup
          `which gem`.chomp
        end
      end
    end

    # Sandbox git command
    def self.sandbox_git_cmd
      if RightScale::Platform.windows?
        # Allow test environment to specify a non-program files location for tools
        if ENV['RS_GIT_EXE']
          ENV['RS_GIT_EXE']
        elsif dir = sandbox_dir
          File.join(dir, 'bin', 'windows', 'git.cmd')
        else
          'git'
        end
      else
        if dir = sandbox_dir
          File.join(dir, 'bin', 'git')
        else
          # Development setup
          `which git`.chomp
        end
      end
    end

  end # AgentConfig

end # RightScale
