#
# Copyright (c) 2009-2012 RightScale Inc
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

    class ChefStateNotInitialized < Exception; end

    class << self
      # Load chef state from file
      #
      # @param [String] agent_id identity
      # @param [String] secret for encryption or nil
      # @param [TrueClass|FalseClass] reset persisted state if true, load it otherwise
      def init(agent_id, secret, reset)
        return true if initialized? && !reset
        @@encoder = MessageEncoder::SecretSerializer.new(agent_id, secret)
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
      def initialized?
        !!defined?(@@attributes)
      end

      # Current node attributes
      #
      # === Return
      # attributes(Hash):: Current node attributes
      def attributes
        ensure_initialized
        @@attributes
      end

      # Current list of scripts that have already executed
      #
      # === Return
      # (Array[(String)]) Scripts that have already executed
      def past_scripts
        ensure_initialized
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
      def attributes=(val)
        ensure_initialized
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
      def merge_attributes(attribs)
        self.attributes = ::RightSupport::Data::HashTools.deep_merge!(attributes, attribs) if attribs
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
      def record_script_execution(nickname)
        ensure_initialized
        new_script = !@@past_scripts.include?(nickname)
        @@past_scripts << nickname if new_script
        # note that we only persist state on successful execution of bundle.
        new_script
      end

      # Save node attributes to file
      # Note: Attributes are saved only when runlist ran on default thread
      #
      # === Return
      # true:: Always return true
      def save_state
        if Cook.instance.has_default_thread?
          begin
            FileUtils.touch(STATE_FILE)
            File.chmod(0600, STATE_FILE)
            write_encoded_data(STATE_FILE, { 'attributes' => @@attributes })
            RightScale::JsonUtilities::write_json(SCRIPTS_FILE, @@past_scripts)
          rescue Exception => e
            Log.warning("Failed to save node attributes", e)
          end
        end
        true
      end

      private
      def ensure_initialized
        raise ChefStateNotInitialized if !initialized?
      end

      # Loads Chef state from file(s), if any.
      #
      # === Return
      # always true
      def load_state
        # load the previously saved Chef node attributes, if any.
        if File.file?(STATE_FILE)
          begin
            js = read_encoded_data(STATE_FILE)
            @@attributes = js['attributes'] || {}
            Log.debug("Successfully loaded chef state")
          rescue Exception => e
            Log.error("Failed to load chef state", e)
          end
        else
          @@attributes = {}
          Log.debug("No previous state to load")
        end

        # load the list of previously run scripts
        @@past_scripts = RightScale::JsonUtilities::read_json(SCRIPTS_FILE) rescue [] if File.file?(SCRIPTS_FILE)
        Log.debug("Past scripts: #{@@past_scripts.inspect}")
        true
      end

      # Encode and save an object to a file
      #
      # === Parameters
      # path(String):: Path to file being written
      # data(Object):: Object to be saved
      #
      # === Return
      # true:: Always return true
      def write_encoded_data(path, data)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        File.open(path, 'w') do |f|
          f.flock(File::LOCK_EX)
          f.write(@@encoder.dump(data))
        end
        true
      end

      # Read encoded content form given file and return the origin al object
      #
      # === Parameters
      # path(String):: Path to file being written
      #
      # === Return
      # data(Object):: Object restored from file content
      def read_encoded_data(path)
        File.open(path, "r") do |f|
          f.flock(File::LOCK_EX)
          return @@encoder.load(f.read)
        end
      end
    end
  end
end
