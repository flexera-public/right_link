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

require 'singleton'
require 'set'

module RightScale
  class LoginManager
    include Singleton

    ROOT_TRUSTED_KEYS_FILE = '/root/.ssh/authorized_keys'
    PUBLIC_KEY_FILES       = ['/etc/ssh/ssh_host_rsa_key.pub',
                              '/etc/ssh/ssh_host_dsa_key.pub']
    ACTIVE_TAG             = 'rs_login:state=active'      
    COMMENT                = /^\s*#/

    # Can the login manager function on this platform?
    #
    # === Return
    # val(true|false) whether LoginManager works on this platform
    def supported_by_platform?
      return RightLinkConfig.platform.linux? || RightLinkConfig.platform.mac?
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

      #As a sanity check, filter out any expired or non-superusers. The core should never send us these guys,
      #but by filtering here additionally we prevent race conditions and handle boundary conditions, as well
      #as allowing our internal expiry timer to simply call us back when a LoginUser expires.
      old_users = InstanceState.login_policy ? InstanceState.login_policy.users : []
      new_users = new_policy.users.select { |u| (u.expires_at == nil || u.expires_at > Time.now) && (u.superuser == true) }
      new_lines, system_lines = merge_keys(old_users, new_users, new_policy.exclusive)
      InstanceState.login_policy = new_policy
      write_keys_file(new_lines)

      tags = [ACTIVE_TAG]
      local_public_keys.each_pair do |algorithm, data|
        tags << "rs_login:#{algorithm}=#{data}"
      end
      AgentTagsManager.instance.add_tags(tags)

      #Schedule a timer to handle any expiration that is planned to happen in the future
      schedule_expiry(new_policy)
      
      #Return a human-readable description of the policy, e.g. for an audit entry
      return describe_policy(new_lines.size, system_lines.size, new_policy)
    end

    protected

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

    # Read ~root/.ssh/authorized_keys if it exists
    #
    # === Return
    # authorized_keys(Array[String]):: list of lines of authorized_keys file
    def read_keys_file
      return [] unless File.exists?(ROOT_TRUSTED_KEYS_FILE)
      File.readlines(ROOT_TRUSTED_KEYS_FILE).map! { |l| l.chomp.strip }
    end

    # Replace the contents of ~root/.ssh/authorized_keys
    #
    # === Parameters
    # keys(Array[(String)]):: list of lines that authorized_keys file should contain
    #
    # === Return
    # true:: always returns true
    def write_keys_file (keys)
      dir = File.dirname(ROOT_TRUSTED_KEYS_FILE)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod(0700, dir)

      File.open(ROOT_TRUSTED_KEYS_FILE, 'w') do |f|
        f.puts "#" * 78
        f.puts "# USE CAUTION WHEN EDITING THIS FILE BY HAND"
        f.puts "# This file is generated based on the RightScale dashboard permission"
        f.puts "# 'server_login'. You can add trusted public keys to the file, but"
        f.puts "# it is regenerated every 24 hours and keys may be added or removed"
        f.puts "# without notice if they correspond to a dashbaord user."
        f.puts "#"
        f.puts "# Instead of editing this file, you probably want to do one of the"
        f.puts "# followng:"
        f.puts "# - Edit dashboard permissions (Settings > Account > Users)"
        f.puts "# - Change your personal public key (Settings > User > SSH)"
        f.puts "#"

        keys.each { |k| f.puts k }
      end

      FileUtils.chmod(0600, ROOT_TRUSTED_KEYS_FILE)
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
      file_lines = read_keys_file

      file_triples = file_lines.map do |l|
        components = LoginPolicy.parse_public_key(l)
        
        if components
          #preserve algorithm, key and comments; discard options (the 0th element)
          next [ components[1], components[2], components[3] ]
        elsif l =~ COMMENT
          next nil
        else
          RightScale::RightLinkLog.error("Malformed (or not SSH2) entry in authorized_keys file: #{l}")
          next nil
        end
      end
      file_triples.compact!
      
      #Find all lines in authorized_keys file that do not correspond to an old user.
      #These are the "system keys" that were not added by RightScale.
      old_users_keys = Set.new
      old_users.each do |u|
        u.public_keys.each do |public_key|
          comp2 = LoginPolicy.parse_public_key(public_key)

          if comp2
            old_users_keys << comp2[2]
          else
            RightScale::RightLinkLog.error("Malformed (or not SSH2) entry in old login policy: #{public_key}")            
          end
        end
      end

      system_triples = file_triples.select { |t| !old_users_keys.include?(t[1]) }
      system_lines   = system_triples.map { |t| t.join(' ') } 
      new_lines      = (new_users.map { |u| u.public_keys }).flatten

      if exclusive
        return [new_lines.sort, []]
      else
        return [(system_lines + new_lines).sort, system_lines.sort]
      end
    end

    # Return a verbose, human-readable description of the login policy, suitable
    # for appending to an audit entry. Contains formatting such as newlines and tabs.
    #
    # === Parameters
    # num_users(Integer) total number of users
    # num_system_users(Integer) number of preserved system keys
    # policy(LoginPolicy) the effective login policy
    #
    # === Return
    # description(String)
    def describe_policy(num_users, num_system_users, policy)
      audit = "#{num_users} total authorized key(s).\n"

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
  end
end
