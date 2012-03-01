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

require 'fileutils'

module RightScale

  # Manages and persists chef state (run list and attributes)
  class ChefState

    # Path to JSON file where current chef state is serialized
    STATE_FILE = File.join(InstanceState::STATE_DIR, 'chef.js')

    # Path to JSON file where past scripts are serialized
    SCRIPTS_FILE = File.join(InstanceState::STATE_DIR, 'past_scripts.js')

    # Load chef state from file
    #
    # === Parameters
    # reset(Boolean):: Discard persisted state if true, load it otherwise
    #
    # === Return
    # true:: Always return true
    def self.init(reset=false)
      return true if initialized? && !reset
      @@attributes = {}
      @@past_scripts = []
      if reset
        save_state
      else
        load_state
      end
      true
    end

    # Was 'init' ever called?
    # Note: Accessing or setting the chef state calls 'init'
    #
    # === Return
    # true:: If 'init' has been called
    # false:: Otherwise
    def self.initialized?
      !!defined?(@@attributes)
    end

    # Current node attributes
    #
    # === Return
    # attributes(Hash):: Current node attributes
    def self.attributes
      init
      @@attributes
    end

    # Current list of scripts that have already executed
    #
    # === Return
    # (Array[(String)]) Scripts that have already executed
    def self.past_scripts
      init
      @@past_scripts
    end

    # Set node attributes
    # Note: can't set it to nil. Setting the attributes to nil will
    # cause the attributes to be initialized if they haven't yet but won't
    # assign the value nil to them.
    #
    # === Parameters
    # attributes(Hash):: Node attributes
    #
    # === Return
    # true:: Always return true
    def self.attributes=(val)
      init
      @@attributes = val if val
      save_state
    end

    # Merge given attributes into node attributes
    #
    # === Parameters
    # attribs(Hash):: Attributes to be merged
    #
    # === Return
    # true:: Always return true
    def self.merge_attributes(attribs)
      self.attributes = RightScale::HashHelper.deep_merge!(attributes, attribs) if attribs
      true
    end

    # Record script execution in scripts file
    #
    # === Parameters
    # nickname(String):: Nickname of RightScript which successfully executed
    #
    # === Return
    # true:: If script was added to past scripts collection
    # false:: If script was already in past scripts collection
    def self.record_script_execution(nickname)
      init
      new_script = !@@past_scripts.include?(nickname)
      @@past_scripts << nickname if new_script
      # note that we only persist state on successful execution of bundle.
      new_script
    end

    # Save chef state to file
    #
    # === Return
    # true:: Always return true
    def self.save_state
      if Cook.instance.has_default_thread?
        begin
          js = { 'attributes' => @@attributes }.to_json
          FileUtils.touch(STATE_FILE)
          File.chmod(0600, STATE_FILE)
          RightScale::JsonUtilities.write_json(STATE_FILE, js)
          RightScale::JsonUtilities::write_json(SCRIPTS_FILE, @@past_scripts)
        rescue Exception => e
          Log.warning("Failed to save Chef state: #{e.message}")
        end
      else
        Log.warning("Ignoring any changes to Chef state due to running on a non-default thread.")
      end
      true
    end

    protected

    # Loads Chef state from file(s), if any.
    #
    # === Return
    # always true
    def self.load_state
      # load the previously saved Chef node attributes, if any.
      if File.file?(STATE_FILE)
        js = RightScale::JsonUtilities::read_json(STATE_FILE) rescue {}
        @@attributes = js['attributes'] || {}
      end
      Log.debug("Initializing chef state with attributes #{@@attributes.inspect}")

      # load the list of previously run scripts
      @@past_scripts = RightScale::JsonUtilities::read_json(SCRIPTS_FILE) rescue [] if File.file?(SCRIPTS_FILE)
      Log.debug("Past scripts: #{@@past_scripts.inspect}")
      true
    end
  end
end
