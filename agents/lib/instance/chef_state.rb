
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

  # Manages and persists chef state (run list and attributes)
  class ChefState

    # Path to JSON file where current chef state is serialized
    STATE_FILE = File.join(InstanceState::STATE_DIR, 'chef.js')

    # Load chef state from file
    #
    # === Parameters
    # reset<TrueClass|FalseClass>:: Discard persisted state if true, load it otherwise
    #
    # === Return
    # true:: Always return true
    def self.init(reset=false)
      @@value = { 'run_list' => [], 'attributes' => {} }
      dir = File.dirname(STATE_FILE)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
      if reset
        save_state
      elsif File.file?(STATE_FILE)
        File.open(STATE_FILE, 'r') { |f| @@value = JSON.load(f) }
      end
      RightLinkLog.debug("Initializing chef state with #{@@value.inspect}")
      true
    end

    # Was 'init' ever called?
    # Note: Accessing or setting the chef state calls 'init'
    #
    # === Return
    # true:: If 'init' has been called
    # false:: Otherwise
    def self.initialized?
      !!(defined? @@value)
    end

    # Current run list
    #
    # === Return
    # run_list<Array>:: List of recipes making up run list
    def self.run_list
      init unless defined? @@value
      run_list = @@value['run_list']
    end

    # Current node attributes
    #
    # === Return
    # attributes<Hash>:: Current node attributes
    def self.attributes
      init unless defined? @@value
      attributes = @@value['attributes']
    end

    # Set run list
    # Note: can't set it to nil. Setting the run list to nil will
    # cause the run list to be initialized if it hasn't yet but won't
    # assign the value nil to it.
    #
    # === Parameters
    # run_list<Array>:: List of recipes making up the run list
    #
    # === Return
    # true:: Always return true
    def self.run_list=(val)
      init unless defined? @@value
      @@value['run_list'] = val if val
      save_state
    end

    # Set node attributes
    # Note: can't set it to nil. Setting the attributes to nil will
    # cause the attributes to be initialized if they haven't yet but won't
    # assign the value nil to them.
    #
    # === Parameters
    # attributes<Hash>:: Node attributes
    #
    # === Return
    # true:: Always return true
    def self.attributes=(val)
      init unless defined? @@value
      @@value['attributes'] = val if val
      save_state
    end

    # Append given run list to current run list
    #
    # === Parameters
    # recipe<String>:: Recipe to be added
    #
    # === Return
    # true:: Always return true
    def self.merge_run_list(list)
      rl = run_list
      list.each { |r| rl << r unless rl.include?(r) }
      self.run_list = rl
      true
    end

    # Merge given attributes into node attributes
    #
    # === Parameters
    # attribs<Hash>:: Attributes to be merged
    #
    # === Return
    # true:: Always return true
    def self.merge_attributes(attribs)
      if attribs
        a = attributes
        deep_merge!(a, attribs)
        self.attributes = a
      end
      true
    end

    # Perform a deep merge between given hashes
    #
    # === Parameters
    # first<Hash>:: Hash to be merged into (modifies it)
    # second<Hash>:: Merged in hash
    #
    # === Return
    # first<Hash>:: Merged hash
    def self.deep_merge!(first, second)
      second.each do |k, v|
        if first[k].is_a?(Hash) and second[k].is_a?(Hash)
          deep_merge!(first[k], second[k])
        else
          first[k] = v
        end
      end if second
      first
    end

    # Save chef state to file
    #
    # === Return
    # true:: Always return true
    def self.save_state
      File.open(STATE_FILE, 'w') { |f| f.puts JSON.dump(@@value) }
      true
    end

  end
end
