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

    include Singleton

    RIGHTSCALE_KEYS_FILE    = '/home/rightscale/.ssh/authorized_keys'
    ACTIVE_TAG              = 'rs_login:state=active'
    RESTRICTED_TAG          = 'rs_login:state=restricted'
    COMMENT                 = /^\s*#/

    def initialize
      require 'etc'
    end

    # Can the login manager function on this platform?
    #
    # === Return
    # val(true|false) whether LoginManager works on this platform
    def supported_by_platform?
      right_platform = RightScale::Platform.linux? || RightScale::Platform.darwin?
      right_user = user_exists?('rightscale')
      right_platform && right_user
    end

    # Enact the login policy specified in new_policy for this system. The policy becomes
    # effective immediately and controls which public keys are trusted for SSH access to
    # the superuser account.
    #
    # === Parameters
    # new_policy(LoginPolicy) the new login policy
    #
    # === Return
    # description(String) a human-readable description of the update, suitable for auditing
    def update_policy(new_policy)
      return false unless supported_by_platform?

      # As a sanity check, filter out any expired users. The core should never send us these guys,
      # but by filtering here additionally we prevent race conditions and handle boundary conditions, as well
      # as allowing our internal expiry timer to simply call us back when a LoginUser expires.
      # All users are added to RightScale account's authorized keys.
      new_users = new_policy.users.select { |u| (u.expires_at == nil || u.expires_at > Time.now) }
      user_lines = modify_keys_to_use_individual_profiles(new_users)

      InstanceState.login_policy = new_policy

      write_keys_file(user_lines, RIGHTSCALE_KEYS_FILE, { :user => 'rightscale', :group => 'rightscale' })

      tags = [ACTIVE_TAG, RESTRICTED_TAG]
      AgentTagsManager.instance.add_tags(tags)

      # Schedule a timer to handle any expiration that is planned to happen in the future
      schedule_expiry(new_policy)

      # Return a human-readable description of the policy, e.g. for an audit entry
      return describe_policy(new_users, new_users.select { |u| u.superuser })
    end

    # Returns prefix command for public key record
    #
    # === Parameters
    # username(String):: account's username
    # email(String):: account's email address
    # data(String):: optional profile_data to be included
    #
    # === Return
    # prefix(String):: command string
    def get_key_prefix(username, email, profile_data=nil)
      if profile_data
        profile = " --profile #{Shellwords.escape(profile_data).gsub('"', '\\"')}"
      else
        profile = ""
      end

      %Q{command="rs_thunk --username #{username} --email #{email}#{profile}" }
    end

    protected

    # Returns array of public keys of specified authorized_keys file
    #
    # === Parameters
    # path(String):: path to authorized_keys file
    #
    # === Return
    # keys(Array[Array]):: array of authorized_key parameters:
    #   key[0](String):: algorithm
    #   key[1](String):: public key
    #   key[2](String):: comment
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
    # === Parameters
    # users(Array) all LoginUsers
    # superusers(Array) subset of LoginUsers who are authorized to act as superusers
    # policy(LoginPolicy) the effective login policy
    #
    # === Return
    # description(String)
    def describe_policy(users, superusers)
      normal_users = users - superusers

      audit = "#{users.size} authorized users " +
              "(#{normal_users.size} normal, #{superusers.size} superuser).\n"

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
    # === Parameters
    # policy(LoginPolicy) policy for which expiry is to be scheduled
    #
    # === Return
    # scheduled(true|false) true if expiry was scheduled, false otherwise
    def schedule_expiry(policy)
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
        update_policy(policy)
      end

      return true
    end

    ##############################
    # === Here is the first version of prototype for Managed Login
    # for RightScale users
    #

    # Creates user accounts and modifies public keys for individual
    # access according to new login policy
    #
    # === Parameters
    # new_users(Array(LoginUser)):: array of updated users list
    #
    # === Return
    # user_lines(Array(String)):: public key lines of user accounts
    def modify_keys_to_use_individual_profiles(new_users)
      user_lines = []

      new_users.each do |u|
        username = create_user(u.username, u.uuid, u.superuser)

        u.public_keys.each do |k|
          user_lines << "#{get_key_prefix(username, u.common_name, u.profile_data)} #{k}"
        end
      end

      return user_lines.sort
    end

    # === OS specific methods

    # Reads specified keys file if it exists
    #
    # === Parameters
    # path(String):: path to authorized_keys file
    #
    # === Return
    # authorized_keys(Array[String]):: list of lines of authorized_keys file
    def read_keys_file(path)
      return [] unless File.exists?(path)
      File.readlines(path).map! { |l| l.chomp.strip }
    end

    # Replace the contents of specified keys file
    #
    # === Parameters
    # keys(Array[(String)]):: list of lines that authorized_keys file should contain
    # keys_file(String):: path to authorized_keys file
    # chown_params(Hash):: additional parameters for user/group
    # === Return
    # true:: always returns true
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

    # Creates user account
    #
    # === Parameters
    # username(String):: username
    # uuid(String):: RightScale user's UUID
    # superuser(Boolean):: flag if user is superuser
    #
    # === Return
    # username(String):: created account's username
    def create_user(username, uuid, superuser)
      uid = LoginUserManager.uuid_to_uid(uuid)

      if uid_exists?(uid, ['rightscale'])
        username = uid_to_username(uid)
      elsif !uid_exists?(uid)
        username  = pick_username(username)
        add_user(username, uid)
        manage_group('rightscale', :add, username) if group_exists?('rightscale')
      else
        raise SystemConflict, "A user with UID #{uid} already exists and is " +
                              "not managed by RightScale"
      end

      action = superuser ? :add : :remove
      manage_group('rightscale_sudo', action, username) if group_exists?('rightscale_sudo')

      username
    end

    # Fetches username from account's UID.
    #
    # === Parameters
    # uid(String):: linux account UID
    #
    # === Return
    # username(String):: account's username or empty string
    def uid_to_username(uid)
      uid = Integer(uid)
      Etc.getpwuid(uid).name
    end

    # Binding for adding user's account record to OS
    #
    # === Parameters
    # username(String):: username
    # uid(String):: account's UID
    #
    # === Return
    # nil
    def add_user(username, uid)
      uid = Integer(uid)

      %x(useradd -s /bin/bash -u #{uid} -m #{Shellwords.escape(username)})

      case $?.exitstatus
      when 0
        home_dir = Etc.getpwnam(username).dir
        FileUtils.chmod(0771, home_dir)

        RightScale::Log.info "User #{username} created successfully"
      end
    end

    # Adds or removes a user from an OS group; does nothing if the user
    # is already in the correct membership state.
    #
    # === Parameters
    # group(String):: group name
    # operation(Symbol):: :add or :remove
    # username(String):: username to add/remove
    #
    # === Raise
    # Raises ArgumentError
    #
    # === Return
    # result(Boolean):: true if user was added/removed; false if
    #
    def manage_group(group, operation, username)
      #Ensure group/user exist; this raises ArgumentError if either does not exist
      Etc.getgrnam(group)
      Etc.getpwnam(username)

      groups = Set.new
      Etc.group { |g| groups << g.name if g.mem.include?(username) }

      case operation
        when :add
          return false if groups.include?(group)
          groups << group
        when :remove
          return false unless groups.include?(group)
          groups.delete(group)
        else
          raise ArgumentError, "Unknown operation #{operation}; expected :add or :remove"
      end

      groups   = Shellwords.escape(groups.to_a.join(','))
      username = Shellwords.escape(username)
      output = %x(usermod -G #{groups} #{username})

      case $?.exitstatus
      when 0
        RightScale::Log.info "Successfully performed group-#{operation} of #{username} to #{group}"
        return true
      else
        RightScale::Log.error "Failed group-#{operation} of #{username} to #{group}: #{output}"
        return false
      end
    end

    # Checks if user with specified name exists in the system.
    #
    # === Parameter
    # name(String):: username
    #
    # === Return
    # exist_status(Boolean):: true if user exists; otherwise false
    def user_exists?(name)
      Etc.getpwnam(name).name == name
    rescue ArgumentError
      false
    end

    # Check if user with specified Unix UID exists in the system, and optionally
    # whether he belongs to all of the specified groups.
    #
    # === Parameters
    # uid(String):: account's UID
    #
    # === Return
    # exist_status(Boolean):: true if exists;otherwise false
    def uid_exists?(uid, groups=[])
      uid = Integer(uid)
      user_exists = Etc.getpwuid(uid).uid == uid
      if groups.empty?
        user_belongs = true
      else
        mem = Set.new
        username = Etc.getpwuid(uid).name
        Etc.group { |g| mem << g.name if g.mem.include?(username) }
        user_belongs = groups.all? { |g| mem.include?(g) }
      end

      user_exists && user_belongs
    rescue ArgumentError
      false
    end

    def group_exists?(name)
      groups = Set.new
      Etc.group { |g| groups << g.name }
      groups.include?(name)
    end

    # Pick a username that does not yet exist on the system. If the given
    # username does not exist, it is returned; else we add a "_1" suffix
    # and continue incrementing the number until we arrive at a username
    # that does not yet exist.
    #
    # === Parameters
    # username(String):: username
    #
    # === Return
    # username(String):: username with possible postfix
    def pick_username(username)
      name = username
      blacklist = Set.new

      while user_exists?(name)
        blacklist << name
        new_name = LoginUserManager.pick_username(name, blacklist)

        if blacklist.include?(new_name)
          raise RangeError, "Misbehaved login policy chose blacklisted name #{new_name}"
        else
          name = new_name
        end
      end

      name
    end
  end
end
