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

require 'rbconfig'

module RightScale

  # Extend AgentConfig for instance agents
  AgentConfig.module_eval do

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
      RightScale::Platform.filesystem.right_link_dynamic_state_dir
    end

    # Path to the file that contains the name of the cloud for this instance
    def self.cloud_file_path
      File.normalize_path(File.join(
        RightScale::Platform.filesystem.right_scale_static_state_dir,
        'cloud'))
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

    # Path to directory for Ruby source code, e.g. cookbooks
    def self.source_code_dir
      @source_code_dir ||= File.join(RightScale::Platform.filesystem.source_code_dir, 'rightscale')
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
    def self.ruby_dir
      ( ENV['RS_RUBY_EXE'] && File.dirname(ENV['RS_RUBY_EXE']) ) ||
        Config::CONFIG["bindir"]
    end

    # Ruby command
    def self.ruby_cmd
      # Allow test environment to specify a non-program files location for tools
      ENV['RS_RUBY_EXE'] ||
        File.join( ruby_dir,
                   Config::CONFIG["RUBY_INSTALL_NAME"] + Config::CONFIG["EXEEXT"] )
    end

    # Sandbox gem command
    def self.gem_cmd
      if RightScale::Platform.windows?
        # Allow test environment to specify a non-program files location for tools
        if ENV['RS_GEM']
          ENV['RS_GEM']
        elsif dir = ruby_dir
          "\"#{ruby_cmd}\" \"#{File.join(dir, 'gem.exe')}\""
        else
          'gem'
        end
      else
        if dir = ruby_dir
          File.join(dir, 'gem')
        else
          # Development setup
          `which gem`.chomp
        end
      end
    end

    # Sandbox git command
    def self.git_cmd
      if RightScale::Platform.windows?
        # Allow test environment to specify a non-program files location for tools
        if ENV['RS_GIT_EXE']
          ENV['RS_GIT_EXE']
        elsif dir = ruby_dir
          File.normalize_path(File.join(dir, '..', '..', 'bin', 'windows', 'git.cmd'))
        else
          'git'
        end
      else
        if dir = ruby_dir
          File.join(dir, 'git')
        else
          # Development setup
          `which git`.chomp
        end
      end
    end

  end # AgentConfig

end # RightScale
