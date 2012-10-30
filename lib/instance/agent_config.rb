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
require 'right_support'
require 'right_agent'

module RightScale
  # Extend AgentConfig for instance agents
  AgentConfig.module_eval do
    # Static (time-invariant) state that is specific to RightLink
    def self.right_link_static_state_dir
      if RightSupport::Platform.linux? || RightSupport::Platform.darwin?
        '/etc/rightscale.d/right_link'
      elsif RightSupport::Platform.windows?
        return RightSupport::Platform.filesystem.pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'rightscale.d', 'right_link'))
      else
        raise NotImplementedError, "Unsupported platform"
      end
    end

    # Dynamic, persistent runtime state that is specific to RightLink
    def self.right_link_dynamic_state_dir
      if RightSupport::Platform::linux? || RightSupport::Platform.darwin?
        '/var/lib/rightscale/right_link'
      elsif RightSupport::Platform.windows?
        return pretty_path(File.join(Dir::COMMON_APPDATA, 'RightScale', 'right_link'))
      else
        raise NotImplementedError, "Unsupported platform"
      end
    end

    def self.right_link_home_dir
      unless @right_link_home_dir
        @right_link_home_dir = ENV['RS_RIGHT_LINK_HOME'] ||
          File.normalize_path(File.join(company_program_files_dir, 'RightLink'))
      end
      @right_link_home_dir
    end

    # Path to right link configuration and internal usage scripts
    def self.private_bin_dir
      if RightSupport::Platform::linux? || RightSupport::Platform.darwin?
        '/opt/rightscale/bin'
      elsif RightSupport::Platform.windows?
        return pretty_path(File.join(right_link_home_dir, 'bin'))
      else
        raise NotImplementedError, "Unsupported platform"
      end
    end

    # Path to RightScale files in parent directory of right_link
    def self.parent_dir
      File.dirname(File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'right_link')))
    end

     # @return [Array] an appropriate sequence of root directories for configuring the RightLink agent
    def self.right_link_root_dirs
      # RightLink certs are written at enrollment time, and live in the
      # 'certs' subdir of the RightLink agent state dir.
      os_root_dir  = File.join(AgentConfig.agent_state_dir)

      # RightLink actors and the agent init directory are both packaged into the RightLink gem,
      # as subdirectories of the gem base directory (siblings of 'lib' and 'bin' directories).
      gem_root_dir = Gem.loaded_specs['right_link'].full_gem_path

      [os_root_dir, gem_root_dir]
    end

    # Path to directory containing persistent RightLink agent state
    def self.agent_state_dir
      AgentConfig::right_link_dynamic_state_dir
    end

    # Path to the file that contains the name of the cloud for this instance
    def self.cloud_file_path
      File.normalize_path(File.join(right_scale_static_state_dir, 'cloud'))
    end

    # Path to directory containing transient cloud-related state (metadata, userdata, etc)
    def self.cloud_state_dir
      @cloud_state_dir ||= File.join(RightSupport::Platform.filesystem.spool_dir, 'cloud')
    end

    # Set path to directory containing transient cloud-related state (metadata, userdata, etc)
    def self.cloud_state_dir=(dir)
      @cloud_state_dir = dir
    end

    # Path to directory for caching instance data
    def self.cache_dir
      @cache_dir ||= File.join(RightSupport::Platform.filesystem.cache_dir, 'rightscale')
    end

    # Set path to directory for caching instance data
    def self.cache_dir=(dir)
      @cache_dir = dir
    end

    # Path to directory for Ruby source code, e.g. cookbooks
    def self.source_code_dir
      @source_code_dir ||= File.join(RightSupport::Platform.filesystem.source_code_dir, 'rightscale')
    end

    # Set path to directory for Ruby source code, e.g. cookbooks
    def self.source_code_dir=(dir)
      @source_code_dir = dir
    end

    # Path to downloaded cookbooks directory
    def self.cookbook_download_dir
      @cookbook_download_dir ||= File.join(cache_dir, 'cookbooks')
    end

    # Path to SCM repository checkouts that contain development cookbooks
    def self.dev_cookbook_checkout_dir
      @dev_cookbook_dir ||= File.join(source_code_dir, 'cookbooks')
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
      dir = RightSupport::Platform.filesystem.sandbox_dir
      File.directory?(dir) ? dir : nil
    end

    # Sandbox ruby command
    def self.sandbox_ruby_cmd
      # Allow test environment to specify a non-program files location for tools
      if ENV['RS_RUBY_EXE']
        ENV['RS_RUBY_EXE']
      elsif RightSupport::Platform.windows?
        if sandbox_dir
          RightSupport::Platform.shell.sandbox_ruby
        else
          'ruby'
        end
      else
        if sandbox_dir && File.exist?(RightSupport::Platform.shell.sandbox_ruby)
          RightSupport::Platform.shell.sandbox_ruby
        else
          # Development setup
          `which ruby`.chomp
        end
      end
    end

    # Sandbox gem command
    def self.sandbox_gem_cmd
      if RightSupport::Platform.windows?
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
      if RightSupport::Platform.windows?
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
