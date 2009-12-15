
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
    # path<Array>:: Dev cookbooks repositories path
    # nil:: Use default cookbook download algorithm
    def self.cookbooks_path
      path = tag_value(COOKBOOK_PATH_TAG)
      path.split(',') if path
    end

    # Name of first recipe in run list that should not be run
    #
    # === Return
    # recipe<String>:: Name of recipe to break execution of sequence on
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

    protected

    # Extract tag value for tag with given namespace and prefix
    #
    # === Parameters
    # prefix<String>:: Tag namespace and prefix
    #
    # === Return
    # value<String>:: Corresponding tag value
    def self.tag_value(prefix)
      tag = InstanceState.startup_tags.detect { |t| t =~ /^#{prefix}/ }
      value = tag[prefix.size..-1] if tag
    end

  end

end
