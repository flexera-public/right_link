
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
      self.attributes = deep_merge!(attributes, attribs) if attribs
      true
    end

    # Perform a deep merge between given hashes
    #
    # === Parameters
    # first(Hash):: Hash to be merged into (modifies it)
    # second(Hash):: Merged in hash
    #
    # === Return
    # first(Hash):: Merged hash
    def self.deep_merge!(first, second)
      second.each do |k, v|
        if hash?(first[k]) && hash?(v)
          deep_merge!(first[k], v)
        else
          first[k] = v
        end
      end if second
      first
    end

    # Produce a patch from two hashes
    # Patch is a hash with the following keys:
    #   - :diff:: Hash with key common to both input hashes and value composed of the corresponding
    #             different values: { :left => <left value>, :right => <right value> }
    #   - :left_only:: Hash composed of items only found in left hash
    #   - :right_only:: Hash composed of items only found in right hash
    #
    # === Parameters
    # left(Hash):: Diff left side
    # right(Hash):: Diff right side
    #
    # === Return
    # res(Hash):: Resulting diff hash
    def self.create_patch(left, right)
      res = empty_patch
      right.each do |k, v|
        if left.include?(k)
          if hash?(v) && hash?(left[k])
            patch = create_patch(left[k], v)
            res[:right_only].merge!({k => patch[:right_only]}) unless patch[:right_only].empty?
            res[:left_only].merge!({k => patch[:left_only]}) unless patch[:left_only].empty?
            res[:diff].merge!({k => patch[:diff]}) unless patch[:diff].empty?
          elsif v != left[k]
            res[:diff].merge!({k => { :left => left[k], :right => v}})
          end
        else
          res[:right_only].merge!({ k => v })
        end
      end
      left.each { |k, v| res[:left_only].merge!({ k => v }) unless right.include?(k) }
      res
    end

    # Empty patch factory
    #
    # === Return
    # p(Hash):: Empty patch hash
    def self.empty_patch
      p = { :diff => {}, :left_only => {}, :right_only => {} }
    end

    # Perform 3-way merge using given target and patch
    # values in target whose keys are in :left_only component of patch are removed
    # values in :right_only component of patch get deep merged into target
    # values in target whose keys are in :diff component of patch and which are identical to left side of patch
    # get overwritten with right side of patch
    #
    # === Parameters
    # target(Hash):: Target hash that patch will be applied to
    # patch(Hash):: Patch to be applied
    #
    # === Return
    # res(Hash):: Result of 3-way merge
    def self.apply_patch(target, patch)
      res = deep_dup(target)
      deep_remove!(res, patch[:left_only])
      deep_merge!(res, patch[:right_only])
      apply_diff!(res, patch[:diff])
      res
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

    # Deep copy of given hash
    # Hash values should be strings, arrays or hashes
    #
    # === Parameters
    # hash(Hash|Mash):: Hash to be deeply copied
    #
    # === Return
    # res(Hash):: Deep copy
    def self.deep_dup(target)
      res = {}
      target.each do |k, v|
        if hash?(v)
          res[k] = deep_dup(v)
        else
          res[k] = (v.duplicable? ? v.dup : v)
        end
      end
      res
    end

    # Remove recursively values that exist in both remove and target from target
    #
    # === Parameters
    # target(Hash):: Hash to remove values from
    # remove(Hash):: Hash containing values to be removed
    #
    # === Return
    # target(Hash):: Modified target hash with values from remove hash removed
    def self.deep_remove!(target, remove)
      remove.each do |k, v|
        if target.include?(k)
          if target[k] == v
            target.delete(k)
          elsif hash?(v) && hash?(target[k])
            deep_remove!(target[k], v)
          end
        end
      end
      target
    end

    # Recursively apply diff component of patch
    #
    # === Parameters
    # target(Hash):: Hash that is modified according to given diff
    # diff(Hash):: :diff component of patch created via 'create_patch'
    #
    # === Return
    # target(Hash):: Modified target hash
    def self.apply_diff!(target, diff)
      diff.each do |k, v|
        if v[:left] && v[:right]
          target[k] = v[:right] if v[:left] == target[k]
        elsif target.include?(k)
          apply_diff!(target[k], v)
        end
      end
      target
    end

    # Check whether given Ruby is a Hash implementation
    # Supports Hash and Mash
    #
    # === Parameters
    # o(Object):: Object to be tested
    #
    # === Return
    # true:: If 'o' is a Hash or a Mash
    # false:: Otherwise
    def self.hash?(o)
      o.is_a?(Hash) || o.is_a?(Mash)
    end

  end
end
