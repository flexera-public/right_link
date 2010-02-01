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

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'right_link_config'))

module RightScale

  # Provide configuration information to instance agent
  class InstanceConfiguration

    # Path to scripts and scripts attachments cache
    CACHE_PATH = File.join(RightScale::RightLinkConfig.platform.filesystem.cache_dir, 'rightscale')

    # Path to downloaded cookbooks
    def self.cookbook_download_path
      @cookbook_download_path ||= File.join(CACHE_PATH, 'cookbooks')
    end

    # Path to RightScript recipes cookbook
    def self.right_scripts_repo_path
      @right_scripts_repo_path ||= File.join(CACHE_PATH, 'right_scripts')
    end

    # Maximum number of times agent should retry to download attachments
    MAX_ATTACH_DOWNLOAD_RETRIES = 10

    # Maximum number of times agent should retry installing packages
    MAX_PACKAGES_INSTALL_RETRIES = 10

  end
 
end