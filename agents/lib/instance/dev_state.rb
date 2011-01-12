
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

require 'fileutils'
require File.normalize_path(File.join(File.dirname(__FILE__), 'json_utilities'))

module RightScale

  # Manages instance dev state
  # Parse dev tags if any and initialize dev state accordingly
  class DevState

    # Dev tags namespace
    DEV_TAG_NAMESPACE = 'rs_agent_dev:'

    # Cookbook path dev tag namespace and prefix
    COOKBOOK_PATH_TAG = "#{DEV_TAG_NAMESPACE}cookbooks_path"

    # Breakpoint dev tag namespace and prefix
    BREAKPOINT_TAG    = "#{DEV_TAG_NAMESPACE}break_point"

    # Download once dev tag namespace and prefix
    DOWNLOAD_ONCE_TAG = "#{DEV_TAG_NAMESPACE}download_cookbooks_once"

    # Path to JSON file where dev state is serialized
    STATE_DIR         = RightScale::RightLinkConfig[:agent_state_dir]
    STATE_FILE        = File.join(STATE_DIR, 'dev_state.js')

    # Reset class state and load persisted state if any
    #
    # === Return
    # true:: Always return true
    def self.init
      @@downloaded = false
      @@initialized = false

      if File.file?(STATE_FILE)
        state = RightScale::JsonUtilities::read_json(STATE_FILE)
        RightLinkLog.debug("Initializing DevState from  #{STATE_FILE} with #{state.inspect}")

        @@downloaded = state['has_downloaded_cookbooks']
      end

      @@initialized = true

      true
    end

    # Is the instance running in dev mode?
    # dev mode tweaks the behavior of the RightLink agent to help
    # the development of Chef recipes.
    # In dev mode, the log level is always debug.
    #
    # === Return
    # true:: If dev tags are defined on this instance
    # false:: Otherwise
    def self.enabled?
      !!tag_value(DEV_TAG_NAMESPACE)
    end

    # Path to cookbooks repos directory. Cookbooks are downloaded to
    # this location if and only if it doesn't exist.
    #
    # === Return
    # path(Array):: Dev cookbooks repositories path
    # nil:: Use default cookbook download algorithm
    def self.cookbooks_path
      path = tag_value(COOKBOOK_PATH_TAG)
      path.split(/, */) if path
    end

    # Name of first recipe in run list that should not be run
    #
    # === Return
    # recipe(String):: Name of recipe to break execution of sequence on
    def self.breakpoint
      recipe = tag_value(BREAKPOINT_TAG)
    end

    # Whether dev cookbooks path should be used instead of standard
    # cookbooks repositories location
    # True if in dev mode and all dev cookbooks repos directories are not empty
    #
    # === Return
    # true:: If dev cookbooks repositories path should be used
    # false:: Otherwise
    def self.use_cookbooks_path?
      res = !!(paths = cookbooks_path)
      return false unless res
      paths.each do |path|
        res = path && File.directory?(path) && Dir.entries(path) != [ '.', '..' ]
        break unless res
      end
      res
    end

    # Whether cookbooks should be downloaded
    # False if either a dev cookbooks path is used or the download once
    # flag is set and cookbooks have already been downloaded
    # Note: we know a cookbook is downloaded when this method is called.
    #       Make sure this stays true.
    #
    # === Return
    # true:: If cookbooks should be downloaded
    # false:: Otherwise
    def self.download_cookbooks?
      # always download unless machine is tagged with a valid cookbooks path or
      # machine is tagged with download once and cookbooks have already been downloaded.
      res = !(use_cookbooks_path? || (has_downloaded_cookbooks? && tag_value(DOWNLOAD_ONCE_TAG) == 'true'))
    end

    # Whether cookbooks have been downloaded
    # False if we have never recorded the fact that cookbooks have been downloaded
    #
    # === Return
    # true:: If cookbooks have be downloaded
    # false:: Otherwise
    def self.has_downloaded_cookbooks?
      init unless initialized?
      !!@@downloaded
    end

    # Set whether cookbooks have been downloaded
    #
    # === Parameters
    # val(Boolean):: Whether cookbooks have been downloaded
    #
    # === Return
    # true:: If cookbooks have be downloaded
    # false:: Otherwise
    def self.has_downloaded_cookbooks=(val)
      init unless initialized?
      if @@downloaded.nil? || @@downloaded != val
        @@downloaded = val
        save_state
      end
      val
    end

    protected

    # Was dev state initialized?
    #
    # === Return
    # true:: if logger has been initialized
    # false:: Otherwise
    def self.initialized?
      defined?(@@initialized) && @@initialized
    end

    # Save dev state to file
    #
    # === Return
    # true:: Always return true
    def self.save_state
      RightScale::JsonUtilities::write_json(RightScale::DevState::STATE_FILE, {"has_downloaded_cookbooks" => has_downloaded_cookbooks?})
      true
    end

    # Extract tag value for tag with given namespace and prefix
    #
    # === Parameters
    # prefix(String):: Tag namespace and prefix
    #
    # === Return
    # value(String):: Corresponding tag value
    def self.tag_value(prefix)
      tag = InstanceState.startup_tags.detect { |t| t =~ /^#{prefix}/ }
      value = tag[prefix.size + 1..-1] if tag
    end

  end

end
