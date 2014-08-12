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

  # Manages and persists cook process state
  class CookState
    # Dev tags namespace
    DEV_TAG_NAMESPACE = 'rs_agent_dev:'

    # Cookbook path dev tag namespace and prefix
    COOKBOOK_PATH_TAG = "#{DEV_TAG_NAMESPACE}cookbooks_path"

    # Breakpoint dev tag namespace and prefix
    BREAKPOINT_TAG    = "#{DEV_TAG_NAMESPACE}break_point"

    # Download once dev tag namespace and prefix
    DOWNLOAD_ONCE_TAG = "#{DEV_TAG_NAMESPACE}download_cookbooks_once"

    # Log level dev tag namespace and prefix
    LOG_LEVEL_TAG     = "#{DEV_TAG_NAMESPACE}log_level"

    # Path to JSON file where dev state is serialized
    STATE_DIR         = RightScale::AgentConfig.agent_state_dir
    STATE_FILE        = File.join(STATE_DIR, 'cook_state.js')

    class << self
      # Reset class state and load persisted state if any
      #
      # === Return
      # true:: Always return true
      def init(reset=false)
        if @state.nil? || reset
          @state = CookState.new
        end
        true
      end

      private
      # not sure if method_missing is the best way to go to expose
      # our state interface as class methods.  If this is not the best
      # approach, then we should look for another...
      def method_missing(method, *args, &block)
        # ensure the state is initialized before calling any methods
        init unless initialized?
        if @state.respond_to?(method)
          @state.send(method, *args, &block)
        else
          super
        end
      end

      # Was cook state initialized?
      #
      # === Return
      # true:: if logger has been initialized
      # false:: Otherwise
      def initialized?
        defined?(@state) && @state
      end
    end

    # Reset class state and load persisted state if any
    #
    # === Return
    # true:: Always return true
    def initialize
      # set some defaults
      @has_downloaded_cookbooks = false
      @reboot                   = false
      @startup_tags             = []
      @log_level                = Logger::INFO
      @log_file                 = nil

      # replace defaults with state on disk
      load_state

      true
    end

    attr_reader :log_level, :log_file, :startup_tags
    attr_writer :has_downloaded_cookbooks

    def has_downloaded_cookbooks?
      !!@has_downloaded_cookbooks
    end

    # Are we rebooting? (needed for RightScripts)
    #
    # === Return
    # res(Boolean):: Whether this instance was rebooted
    def reboot?
      !!@reboot
    end

    # Determines the developer log level, if any, which forces and supercedes
    # all other log level configurations.
    #
    # === Return
    # level(Token):: developer log level or nil
    def dev_log_level
      if value = tag_value(LOG_LEVEL_TAG)
        value = value.downcase.to_sym
        value = nil unless [:debug, :info, :warn, :error, :fatal].include?(value)
      end
      value
    end

    # Path to cookbooks repos directory. Cookbooks are downloaded to
    # this location if and only if it doesn't exist.
    #
    # === Return
    # path(Array):: Dev cookbooks repositories path
    # nil:: Use default cookbook download algorithm
    def cookbooks_path
      path = tag_value(COOKBOOK_PATH_TAG)
      path.split(/, */) if path
    end

    # Name of first recipe in run list that should not be run
    #
    # === Return
    # recipe(String):: Name of recipe to break execution of sequence on
    def breakpoint_recipe
      recipe = tag_value(BREAKPOINT_TAG)
    end

    # Whether dev cookbooks path should be used instead of standard
    # cookbooks repositories location
    # True if in dev mode and all dev cookbooks repos directories are not empty
    #
    # === Return
    # true:: If dev cookbooks repositories path should be used
    # false:: Otherwise
    def use_cookbooks_path?
      res = !!(paths = cookbooks_path)
      return false unless res
      paths.each do |path|
        res = path && File.directory?(path) && Dir.entries(path) != ['.', '..']
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
    def download_cookbooks?
      # always download unless machine is tagged with a valid cookbooks path or
      # machine is tagged with download once and cookbooks have already been downloaded.
      res = !(use_cookbooks_path? || (has_downloaded_cookbooks? && download_once?))
    end

    # Whether cookbooks should be downloaded only once
    #
    # === Return
    # true:: If cookbooks should be downloaded only once for this instance
    # false:: Otherwise
    def download_once?
      tag_value(DOWNLOAD_ONCE_TAG) == 'true'
    end

    # Current logger severity
    #
    # === Return
    # level(Integer):: one of Logger::INFO ... Logger::FATAL
    def log_level
      case @log_level
      when Symbol, String
        Log.level_from_sym(@log_level.to_sym)
      else
        @log_level
      end
    end

    # Re-initialize then merge given state
    #
    # === Parameters
    # state_to_merge(RightScale::InstanceState):: InstanceState to be passed on to Cook
    # overrides(Hash):: Hash keyed by state name that will override state_to_merge
    #
    # === Return
    # true:: Always
    def update(state_to_merge, overrides = {})
      # only merge state if state to be merged has values
      @startup_tags = state_to_merge.startup_tags if state_to_merge.respond_to?(:startup_tags)
      @reboot       = state_to_merge.reboot?      if state_to_merge.respond_to?(:reboot?)
      @log_level    = state_to_merge.log_level    if state_to_merge.respond_to?(:log_level)
      if state_to_merge.respond_to?(:log_file) && state_to_merge.respond_to?(:value)
        @log_file = state_to_merge.log_file(state_to_merge.value)
      end

      @startup_tags = overrides[:startup_tags] if overrides.has_key?(:startup_tags)
      @reboot       = overrides[:reboot]       if overrides.has_key?(:reboot)
      @log_file     = overrides[:log_file]     if overrides.has_key?(:log_file)

      # check the log level again after the startup_tags have been updated or
      # overridden.
      if overrides.has_key?(:log_level)
        @log_level = overrides[:log_level]
      elsif tagged_log_level = dev_log_level
        @log_level = tagged_log_level
      end

      save_state

      true
    end

    protected

    # Extract tag value for tag with given namespace and prefix
    #
    # === Parameters
    # prefix(String):: Tag namespace and prefix
    #
    # === Return
    # value(String):: Corresponding tag value
    def tag_value(prefix)
      tag = nil
      tag = @startup_tags && @startup_tags.detect { |t| t =~ /^#{prefix}/ }
      value = tag[prefix.size + 1..-1] if tag
      value
    end

    # Save dev state to file
    #
    # === Return
    # true:: Always return true
    def save_state
      # start will al state to be saved
      state_to_save = { 'startup_tags' => startup_tags,
                      'reboot' => reboot?,
                      'log_level' => log_level }

      # only save a log file one is defined
      if log_file
        state_to_save['log_file'] = log_file
      end

      # only save persist the fact we downloaded cookbooks if we are in dev mode
      if download_once?
        state_to_save['has_downloaded_cookbooks'] = has_downloaded_cookbooks?
      end

      RightScale::JsonUtilities::write_json(RightScale::CookState::STATE_FILE, state_to_save)
      true
    end

    # load dev state from disk
    #
    # === Return
    # true:: Always return true
    def load_state
      if File.file?(STATE_FILE)
        state = RightScale::JsonUtilities::read_json(STATE_FILE)
        @log_level = state['log_level'] || Logger::INFO
        Log.info("Initializing CookState from  #{STATE_FILE} with #{state.inspect}") if @log_level == Logger::DEBUG

        @has_downloaded_cookbooks = state['has_downloaded_cookbooks']
        @startup_tags = state['startup_tags'] || []
        @reboot = state['reboot']
        @log_file = state['log_file'] # nil if not in state loaded from disk
      end
      true
    end
  end
end
