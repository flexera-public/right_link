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

require 'singleton'
require 'set'

module RightScale
  class LoginManager
    class SystemConflict < SecurityError; end

    include RightSupport::Ruby::EasySingleton

    CONFIG_YAML_FILE = File.normalize_path(File.join(RightScale::Platform.filesystem.right_link_static_state_dir, 'features.yml'))

    CONFIG=\
      if File.exists?(CONFIG_YAML_FILE)
        RightSupport::Config.features(CONFIG_YAML_FILE)
      else
        RightSupport::Config.features({})
      end


    RIGHTSCALE_KEYS_FILE    = '/home/rightscale/.ssh/authorized_keys'
    ACTIVE_TAG              = 'rs_login:state=active'
    RESTRICTED_TAG          = 'rs_login:state=restricted'
    COMMENT                 = /^\s*#/

    def initialize
      require 'etc'
    end

    # Can the login manager function on this platform?
    #
    # == Returns:
    # @return [TrueClass] if LoginManager works on this platform
    # @return [FalseClass] if LoginManager does not work on this platform
    #
    def supported_by_platform?
      right_platform = RightScale::Platform.linux?
      # avoid calling user_exists? on unsupported platform(s)
      right_platform && LoginUserManager.user_exists?('rightscale') && CONFIG['managed_login']['enable']
    end

    # Enact the login policy specified in new_policy for this system. The policy becomes
    # effective immediately and controls which public keys are trusted for SSH access to
    # the superuser account.
    #
    # == Parameters:
    # @param [RightScale::LoginPolicy] New login policy
    # @param [String] Serialized instance agent identity
    #
    # == Yields:
    # @yield [String] audit content yielded to the block provided
    #
    # == Returns:
    # @return [TrueClass] if supported by given platform
    # @return [FalseClass] if not supported by given platform
    #
    def update_policy(new_policy, agent_identity)
      return false unless supported_by_platform?

      # As a sanity check, filter out any expired users. The core should never send us these guys,
      # but by filtering here additionally we prevent race conditions and handle boundary conditions, as well
      # as allowing our internal expiry timer to simply call us back when a LoginUser expires.
      # All users are added to RightScale account's authorized keys.
      new_users = new_policy.users.select { |u| (u.expires_at == nil || u.expires_at > Time.now) }
      update_users(new_users, agent_identity, new_policy) do |audit_content|
        yield audit_content if block_given?
      end

      true
    end

    # Returns prefix command for public key record
    #
    # == Parameters:
    # @param [String] account's username
    # @param [String] account's email address
    # @param [String] account's uuid
    # @param [Boolean] designates whether the account has superuser privileges
    # @param [String] optional profile_data to be included
    #
    # == Returns:
    # @return [String] command string
    #
    def get_key_prefix(username, email, uuid, superuser, profile_data = nil)
      if profile_data
        profile = " --profile #{Shellwords.escape(profile_data).gsub('"', '\\"')}"
      else
        profile = ""
      end

      superuser = superuser ? " --superuser" : ""

      %Q{command="rs_thunk --username #{username} --uuid #{uuid}#{superuser} --email #{email}#{profile}" }
    end

    protected

    # For any user with a public key fingerprint but no public key, obtain the public key
    # from the old policy or by querying RightScale using the fingerprints
    # Remove a user if no public keys are available for it
    #
    # == Parameters:
    # @param [Array<LoginUsers>] Login users whose public keys are to be populated
    # @param [String] Serialized instance agent identity
    # @param [RightScale::LoginPolicy] New login policy
    #
    # == Yields:
    # @yield [String] audit content yielded to the block provided
    #
    # == Returns:
    # @return [TrueClass] always returns true
    #
    def update_users(users, agent_identity, new_policy)
      # Create cache of public keys from stored instance state
      # but there won't be any on initial launch
      public_keys_cache = {}
      if old_policy = InstanceState.login_policy
        public_keys_cache = old_policy.users.inject({}) do |keys, user|
          user.public_key_fingerprints ||= user.public_keys.map { |key| fingerprint(key, user.username) }
          user.public_keys.zip(user.public_key_fingerprints).each { |(k, f)| keys[f] = k if f }
          keys
        end
      end

      # See if there are any missing keys and if so, send a request to retrieve them
      # Then make one more pass to populate any missing keys and reject any that are still not populated
      unless (missing = populate_public_keys(users, public_keys_cache)).empty?
        payload = {:agent_identity => agent_identity, :public_key_fingerprints => missing.map { |(u, f)| f }}
        request = RightScale::IdempotentRequest.new("/key_server/retrieve_public_keys", payload)

        request.callback do |public_keys|
          missing = populate_public_keys(users, public_keys, remove_if_missing = true)
          finalize_policy(new_policy, agent_identity, users, missing.map { |(u, f)| u }.uniq) do |audit_content|
            yield audit_content
          end
        end

        request.errback do |error|
          Log.error("Failed to retrieve public keys for users #{missing.map { |(u, f)| u.username }.uniq.inspect}: #{error}")
          missing = populate_public_keys(users, {}, remove_if_missing = true)
          finalize_policy(new_policy, agent_identity, users, missing.map { |(u, f)| u }.uniq) do |audit_content|
            yield audit_content
          end
        end

        request.run
      else
        finalize_policy(new_policy, agent_identity, users, missing.map { |(u, f)| u }.uniq) do |audit_content|
          yield audit_content
        end
      end

      true
    end

    # Manipulates the authorized_keys file to match the given login policy
    # Schedules expiration of users from policy and audits the policy in
    # a human-readable format
    #
    # == Parameters:
    # @param [RightScale::LoginPolicy] New login policy
    # @param [String] Serialized instance agent identity
    # @param [Array<LoginUsers>] Array of updated users
    # @param [Array<LoginUsers>] Array of users with public keys missing
    #
    # == Yields:
    # @yield [String] audit content yielded to the block provided
    #
    # == Returns:
    # @return [TrueClass] always returns true
    #
    def finalize_policy(new_policy, agent_identity, new_users, missing)
      user_lines = modify_keys_to_use_individual_profiles(new_users)

      InstanceState.login_policy = new_policy

      write_keys_file(user_lines, RIGHTSCALE_KEYS_FILE, { :user => 'rightscale', :group => 'rightscale' })

      tags = [ACTIVE_TAG, RESTRICTED_TAG]
      AgentTagManager.instance.add_tags(tags)

      # Schedule a timer to handle any expiration that is planned to happen in the future
      schedule_expiry(new_policy, agent_identity)

      # Yield a human-readable description of the policy, e.g. for an audit entry
      yield describe_policy(new_users, new_users.select { |u| u.superuser }, missing)

      true
    end

    # Populate missing public keys from old public keys using associated fingerprints
    # Also populate any missing fingerprints where possible
    #
    # == Parameters:
    # @param [Array<LoginUser>] Login users whose public keys are to be updated if nil
    # @param [Hash<String, String>] Public keys with fingerprint as key and public key as value
    # @param [Boolean] Whether to remove a user's public key if it cannot be obtained
    #           and the user itself if none of its public keys can be obtained
    #
    # == Returns:
    # @return [Array<LoginUser,String] User and fingerprint for each missing public key
    #
    def populate_public_keys(users, public_keys_cache, remove_if_missing = false)
      missing = []
      users.reject! do |user|
        reject = false

        # Create any missing fingerprints from the public keys so that fingerprints
        # are as populated as possible
        user.public_key_fingerprints ||= user.public_keys.map { |key| fingerprint(key, user.username) }
        user.public_key_fingerprints = user.public_keys.zip(user.public_key_fingerprints).map do |(k, f)|
          f || fingerprint(k, user.username)
        end

        # Where possible use cache of old public keys to populate any missing ones
        public_keys = user.public_keys.zip(user.public_key_fingerprints).inject([]) do |keys, (k, f)|
          if f
            if k ||= public_keys_cache[f]
              keys << k
            else
              if remove_if_missing
                Log.error("Failed to obtain public key with fingerprint #{f.inspect} for user #{user.username}, " +
                          "removing it from login policy")
              else
                keys << k
              end
              missing << [user, f]
            end
          else
            Log.error("Failed to obtain public key with fingerprint #{f.inspect} for user #{user.username}, " +
                      "removing it from login policy")
          end
          keys
        end

        # Reject user if none of its public keys could be populated
        # This will not happen unless remove_if_missing is true
        if public_keys.empty?
          reject = true
        else
          user.public_keys = public_keys
        end
        reject
      end
      missing
    end

    # Create fingerprint for public key
    #
    # == Parameters:
    # @param [String] RSA public key
    # @param [String] Name of user owning this key
    #
    # == Return:
    # @return [String] Fingerprint for key if it could create it
    # @return [NilClass] if it could not create it
    #
    def fingerprint(public_key, username)
      LoginUser.fingerprint(public_key) if public_key
    rescue Exception => e
      Log.error("Failed to create public key fingerprint for user #{username}", e)
      nil
    end

    # Returns array of public keys of specified authorized_keys file
    #
    # == Parameters:
    # @param [String] path to authorized_keys file
    #
    # == Returns:
    #
    # @return [Array<Array(String, String, String)>] array of authorized_key parameters: algorith, public key, comment
    #
    def load_keys(path)
      file_lines = read_keys_file(path)

      keys = []
      file_lines.map do |l|
        components = LoginPolicy.parse_public_key(l)

        if components
          #preserve algorithm, key and comments; discard options (the 0th element)
          keys << [ components[1], components[2], components[3] ]
        elsif l =~ COMMENT
          next
        else
          RightScale::Log.error("Malformed (or not SSH2) entry in authorized_keys file: #{l}")
          next
        end
      end

      keys
    end

    # Return a verbose, human-readable description of the login policy, suitable
    # for appending to an audit entry. Contains formatting such as newlines and tabs.
    #
    # == Parameters:
    # @param [Array<LoginUser>] All LoginUsers
    # @param [Array<LoginUser>] Subset of LoginUsers who are authorized to act as superusers
    # @param [LoginPolicy] Effective login policy
    # @param [Array<LoginUser>] Users for which a public key could not be obtained
    #
    # == Returns:
    # @return [String] description
    #
    def describe_policy(users, superusers, missing = [])
      normal_users = users - superusers

      audit = "#{users.size} authorized users (#{normal_users.size} normal, #{superusers.size} superuser).\n"
      audit << "Public key missing for #{missing.map { |u| u.username }.join(", ") }.\n" if missing.size > 0

      #unless normal_users.empty?
      #  audit += "\nNormal users:\n"
      #  normal_users.each do |u|
      #    audit += "  #{u.common_name.ljust(40)} #{u.username}\n"
      #  end
      #end
      #
      #unless superusers.empty?
      #  audit += "\nSuperusers:\n"
      #  superusers.each do |u|
      #    audit += "  #{u.common_name.ljust(40)} #{u.username}\n"
      #  end
      #end

      return audit
    end

    # Given a LoginPolicy, add an EventMachine timer to handle the
    # expiration of LoginUsers whose expiry time occurs in the future.
    # This ensures that their login privilege expires on time and in accordance
    # with the policy (so long as the agent is running). Expiry is handled by
    # taking the policy exactly as it was received and passing it to #update_policy,
    # which already knows how to filter out users who are expired at the time the policy
    # is applied.
    #
    # == Parameters:
    # @param [LoginPolicy] Policy for which expiry is to be scheduled
    # @param [String] Serialized instance agent identity
    #
    # == Returns:
    # @return [TrueClass] if expiry was scheduled
    # @return [FalseClass] if expiry was not scheduled
    #
    def schedule_expiry(policy, agent_identity)
      if @expiry_timer
        @expiry_timer.cancel
        @expiry_timer = nil
      end

      next_expiry = policy.users.map { |u| u.expires_at }.compact.min
      return false unless next_expiry
      delay = next_expiry.to_i - Time.now.to_i + 1

      #Clip timer to one day (86,400 sec) to work around EM timer bug involving
      #32-bit integer. This works because update_policy is idempotent and can
      #be safely called at any time. It will "reconverge" if it is called when
      #no permissions have changed.
      delay = [delay, 86_400].min

      return false unless delay > 0
      @expiry_timer = EventMachine::Timer.new(delay) do
        update_policy(policy, agent_identity)
      end

      return true
    end

    # Here is the first version of prototype for Managed Login for RightScale users.
    # Creates user accounts and modifies public keys for individual
    # access according to new login policy
    #
    # == Parameters:
    # @param [Array<LoginUser>] array of updated users list
    #
    # == Returns:
    # @return [Array<String>] public key lines of user accounts
    #
    def modify_keys_to_use_individual_profiles(new_users)
      user_lines = []

      new_users.each do |u|
        u.public_keys.each do |k|
          user_lines << "#{get_key_prefix(u.username, u.common_name, u.uuid, u.superuser, u.profile_data)} #{k}"
        end
      end

      return user_lines.sort
    end

    # === OS specific methods

    # Reads specified keys file if it exists
    #
    # == Parameters
    # @param [String] path to authorized_keys file
    #
    # == Return
    # @return [Array<String>] list of lines of authorized_keys file
    #
    def read_keys_file(path)
      return [] unless File.exists?(path)
      File.readlines(path).map! { |l| l.chomp.strip }
    end

    # Replace the contents of specified keys file
    #
    # == Parameters:
    # @param [Array<String>] list of lines that authorized_keys file should contain
    # @param [String] path to authorized_keys file
    # @param [Hash] additional parameters for user/group
    #
    # == Returns:
    # @return [TrueClass] always returns true
    #
    def write_keys_file(keys, keys_file, chown_params = nil)
      dir = File.dirname(keys_file)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod(0700, dir)

      File.open(keys_file, 'w') do |f|
        f.puts "#" * 78
        f.puts "# USE CAUTION WHEN EDITING THIS FILE BY HAND"
        f.puts "# This file is generated based on the RightScale dashboard permission"
        f.puts "# 'server_login'. You can add trusted public keys to the file, but"
        f.puts "# it is regenerated every 24 hours and keys may be added or removed"
        f.puts "# without notice if they correspond to a dashboard user."
        f.puts "#"
        f.puts "# Instead of editing this file, you probably want to do one of the"
        f.puts "# following:"
        f.puts "# - Edit dashboard permissions (Settings > Account > Users)"
        f.puts "# - Change your personal public key (Settings > User > SSH)"
        f.puts "#"

        keys.each { |k| f.puts k }
      end

      FileUtils.chmod(0600, keys_file)
      FileUtils.chown_R(chown_params[:user], chown_params[:group], File.dirname(keys_file)) if chown_params
      return true
    end
  end
end
