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
    include Singleton

    SUPERUSER_KEYS_FILE = '/root/.ssh/authorized_keys'
    RIGHTSCALE_KEYS_FILE = '/home/rightscale/.ssh/authorized_keys'
    PUBLIC_KEY_FILES       = ['/etc/ssh/ssh_host_rsa_key.pub',
                              '/etc/ssh/ssh_host_dsa_key.pub']
    ACTIVE_TAG             = 'rs_login:state=active'
    COMMENT                = /^\s*#/

    # Can the login manager function on this platform?
    #
    # === Return
    # val(true|false) whether LoginManager works on this platform
    def supported_by_platform?
      return RightScale::Platform.linux? || RightScale::Platform.darwin?
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
      # Non-superusers should be added to rightscale account's authorized_keys.
      old_users = InstanceState.login_policy ? InstanceState.login_policy.users : []
      new_users = new_policy.users.select { |u| (u.expires_at == nil || u.expires_at > Time.now) }
      superuser_lines, non_superuser_lines, system_lines = merge_keys(old_users, new_users, new_policy.exclusive)

      InstanceState.login_policy = new_policy

      write_keys_file(superuser_lines, SUPERUSER_KEYS_FILE)
      write_keys_file(non_superuser_lines, RIGHTSCALE_KEYS_FILE)

      tags = [ACTIVE_TAG]
      AgentTagsManager.instance.add_tags(tags)

      #Schedule a timer to handle any expiration that is planned to happen in the future
      schedule_expiry(new_policy)

      #Return a human-readable description of the policy, e.g. for an audit entry
      return describe_policy(superuser_lines.size, non_superuser_lines.size, system_lines.size, new_policy)
    end

    #protected

    # Read various public keys from /etc/ssh
    #
    # === Return
    # keys(Hash):: map of algorithm-name => public key material
    def local_public_keys
      keys = {}

      PUBLIC_KEY_FILES.each do |f|
        if File.exist?(f) && File.readable?(f) && (data = File.read(f))
          data      = data.split
          algorithm = data[0].split('-').last
          key       = data[1]
          keys[algorithm] = key
        end
      end

      keys
    end

    # Read /root/.ssh/authorized_keys if it exists
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

    # Replace the contents of ~root/.ssh/authorized_keys
    #
    # === Parameters
    # keys(Array[(String)]):: list of lines that authorized_keys file should contain
    # keys_file(String):: path to authorized_keys file
    #
    # === Return
    # true:: always returns true
    def write_keys_file(keys, keys_file)
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
        f.puts "# followng:"
        f.puts "# - Edit dashboard permissions (Settings > Account > Users)"
        f.puts "# - Change your personal public key (Settings > User > SSH)"
        f.puts "#"

        keys.each { |k| f.puts k }
      end

      FileUtils.chmod(0600, keys_file)
      return true
    end

    # Perform a three-way merge of the old login policy (if applicable), authorized_keys file
    # (if applicable) and the new login policy. Ensures that any policy users that no longer
    # have access are removed from the authorized keys, without removing "system" keys from
    # the authorized keys file. System keys are defined as any line of authorized_keys
    # that we did not put there.
    #
    # If exclusive=true, then system keys are not preserved; although a merge is still performed,
    # the return value is simply the public keys of new_users.
    #
    # === Parameters
    # old_users(Array[(LoginUser)]) old login policy's users
    # new_users(Array[(LoginUser)]) new login policy's users
    # exclusive(true|false) if true, system keys are not preserved
    #
    # === Return
    # authorized_keys(Array[(String)]) new set of trusted public keys
    #
    # === Raise
    # Exception:: desc
    def merge_keys(old_users, new_users, exclusive)
      superuser_keys = load_keys(SUPERUSER_KEYS_FILE)

      # Find all lines in authorized_keys file that do not correspond to an old user.
      # These are the "system keys" that were not added by RightScale.
      old_users_keys = Set.new
      old_users.each do |u|
        u.public_keys.each do |public_key|
          comp2 = LoginPolicy.parse_public_key(public_key)

          if comp2
            old_users_keys << comp2[2]
          else
            RightScale::Log.error("Malformed (or not SSH2) entry in old login policy: #{public_key}")
          end
        end
      end

      # Triples of algorithm, public key and comment
      system_keys   = superuser_keys.select { |t| !old_users_keys.include?(t[1]) }
      system_lines  = system_keys.map { |t| t.join(' ') } 

      superuser_lines, non_superuser_lines = modify_keys_to_use_individual_profiles(new_users)

      if exclusive
        return [superuser_lines.sort, non_superuser_lines, []]
      else
        return [(system_lines + superuser_lines).sort, non_superuser_lines.sort, system_lines.sort]
      end
    end

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
    # num_superusers(Integer) total number of superusers
    # num_non_superusers(Integer) total number of non-superusers
    # num_system_users(Integer) number of preserved system keys
    # policy(LoginPolicy) the effective login policy
    #
    # === Return
    # description(String)
    def describe_policy(num_superusers, num_non_superusers, num_system_users, policy)
      audit = "#{num_superusers} total superusers' authorized key(s).\n"
      audit += "#{num_non_superusers} total non-superusers' authorized key(s).\n"

      unless policy.exclusive
        audit += "Non-exclusive policy; preserved #{num_system_users} non-RightScale key(s).\n"
      end
      if policy.users.empty?
        audit += "No authorized RightScale users."
      else
        audit += "Authorized RightScale users:\n"
        policy.users.each do |u|
          audit += "  #{u.common_name.ljust(40)} #{u.username}\n"
        end
      end

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

    # === Here is the first version of prototype for Managed Login
    # for RightScale users
    #
    # It creates users for Managed SSH login
    def create_user(username, uuid, superuser)
      uid = fetch_uid(uuid)

      if uid_exists?(uid)
        fetch_username(uid)
      else
        username  = pick_username(username)
        group     = fetch_group(superuser)
        add_user(username, group, uid)
        username
      end
    end

    # Fetches username from account's UID.
    #
    # === Parameters
    # uid(String):: linux account UID
    #
    # === Return
    # username(String):: account's username or empty string
    def fetch_username(uid)
      user_line = %x(grep '^.*:.:#{uid}' /etc/passwd)
      user_line.scan(/^(\w+)/).to_s
    end

    def add_user(username, group, uid)
      # We need to use user_id integer instead of translation uuid to integer!
      %x(useradd -s /bin/bash -g #{group} -u #{uid} -m #{username})

      case $?.exitstatus
      when 0
        RightScale::Log.info "User #{username} created successfully"
      end
    end

    # Checks if user with specified name exists in the system.
    #
    # id command returns information about user and exit status. 
    # It can be 0 for success; > 0 for error. 
    def user_exists?(name)
      %x(id #{name})

      $?.exitstatus == 0
    end

    # Checks if user with specified UID exists in the system.
    #
    # Linux /etc/passwd file has the following structure:
    # 
    # <username>:x(hidden password):<UID>:<GID>:<info>:<homedir>:<command>
    # 
    # If command matches the defined regexp it means user with such UID
    # exists.
    def uid_exists?(uid)
      not %x(grep '.*:.:#{uid}' /etc/passwd).empty?
    end

    # Temporary hack to get username from the user email. Will be changed
    # by adding extra field to LoginPolicy and LoginUser.
    #
    # Method picks username from common_name(email).
    # Then it checks for username existance incrementing postfix until
    # suitable name is found.
    def pick_username(username)
      name = username

      index = 0
      while user_exists?(name)
        index += 1
        name = "#{username}_#{index}"
      end
      
      name
    end

    # Transforms RightScale UUID to linux uid.
    def fetch_uid(uuid)
      uuid.to_i + 4096
    end

    def fetch_group(superuser)
      superuser ? "root" : "admin"
    end

    # Sorts kyes for users and superusers; creates user accounts
    # according to new login policy
    #
    # === Parameters
    # new_users(Array(LoginUser)):: array of updated users list
    #
    # === Return
    # superuser_lines(Array(String)):: public key lines of superuser
    # accounts
    # non_superuser_lines(Array(String)):: public key lines of
    # non-superuser accounts
    def modify_keys_to_use_individual_profiles(new_users)
      superuser_lines = Array.new
      non_superuser_lines = Array.new

      new_users.map do |u|
        username = create_user(u.username, u.uuid, u.superuser)

        next unless username

        u.public_keys.each do |k|
          # TBD for thunking
          # non_superuser_lines << %Q{command="rs_thunk --uid #{u.uuid} --email #{u.email} --profile='#{u.home_dir}'" } + k
          non_superuser_lines << "command=\"cd /home/#{username}; su #{username}\" " + k
          superuser_lines << k if u.superuser
        end
      end

      return superuser_lines, non_superuser_lines
    end
  end
end
