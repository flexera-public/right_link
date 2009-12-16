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
    ACTIVE_TAG             = 'rs_login:state=active'      

    # Can the login manager function on this platform?
    #
    # === Return
    # val<true|false> whether LoginManager works on this platform
    def supported_by_platform?
      return RightLinkConfig.platform.linux? || RightLinkConfig.platform.mac?
    end

    # Enact the login policy specified in new_policy for this system. The policy becomes
    # effective immediately and controls which public keys are trusted for SSH access to
    # the superuser account.
    #
    # === Parameters
    # new_policy<LoginPolicy> the new login policy
    #
    # === Return
    # description<String> a human-readable description of the update, suitable for auditing
    def update_policy(new_policy)
      return false unless supported_by_platform?

      #As a sanity check, filter out any expired or non-superusers. The core should never send us these guys,
      #but by filtering here additionally we prevent race conditions and handle boundary conditions.
      old_users = InstanceState.login_policy ? InstanceState.login_policy.users : []
      new_users = new_policy.users.select { |u| (u.expires_at == nil || u.expires_at > Time.now) && (u.superuser == true) }
      new_lines, system_lines = merge_keys(old_users, new_users, new_policy.exclusive)
      InstanceState.login_policy = new_policy
      write_keys_file(new_lines)
      AgentTagsManager.instance.add_tags(ACTIVE_TAG)
      return describe_policy(new_lines.size, system_lines.size, new_policy)
    end

    protected

    # Read ~root/.ssh/authorized_keys if it exists
    #
    # === Return
    # authorized_keys<Array[<String>]> list of lines of authorized_keys file
    def read_keys_file
      return [] unless File.exist?(ROOT_TRUSTED_KEYS_FILE)
      File.readlines(ROOT_TRUSTED_KEYS_FILE).map! { |l| l.chomp.strip }
    end

    # Replace the contents of ~root/.ssh/authorized_keys
    #
    # === Parameters
    # keys<Array[<String>]> list of lines that authorized_keys file should contain
    #
    # === Return
    # true:: always returns true
    def write_keys_file (keys)
      dir = File.dirname(ROOT_TRUSTED_KEYS_FILE)
      FileUtils.mkdir_p(dir)
      FileUtils.chmod(0700, dir)

      File.open(ROOT_TRUSTED_KEYS_FILE, 'w') do |f|
        keys.each { |k| f.puts k }
      end

      FileUtils.chmod(0600, ROOT_TRUSTED_KEYS_FILE)
      return true
    end

    # Perform a three-way merge of the old login policy (if applicable), authorized_keys file
    # (if applicable) and the new login policy. Ensures that any policy users that no longer
    # have access are removed from the authorized keys, without removing "system" keys from
    # the authorized keys file (where system keys are defined as any line of authorized_keys
    # that we did not put there).
    #
    # If exclusive=true, then system keys are not preserved; although a merge is still performed,
    # the return value is simply the public keys of new_users.
    #
    # === Parameters
    # old_users<Array[<LoginUser>]> old login policy's users
    # new_users<Array[<LoginUser>]> new login policy's users
    # exclusive<true|false> if true, system keys are not preserved
    #
    # === Return
    # authorized_keys<Array[<String>]> new set of trusted public keys
    #
    # === Raise
    # Exception:: desc
    def merge_keys(old_users, new_users, exclusive)
      file_lines = read_keys_file

      file_triples = file_lines.map do |l|
        elements = l.split(/\s+/)
        if elements.length == 3
          next elements
        else
          RightScale::RightLinkLog.error("Malformed public key in authorized_keys file: #{l}")
          next nil
        end
      end
      file_triples.compact!
      
      #Find all lines in authorized_keys file that do not correspond to an old user.
      #These are the "system keys" that were not added by RightScale.
      old_users_keys = Set.new
      old_users.each { |u| old_users_keys << u.public_key.split(/\s+/)[1] }

      system_triples = file_triples.select { |t| !old_users_keys.include?(t[1]) }
      system_lines   = system_triples.map { |t| t.join(' ') } 
      new_lines      = new_users.map { |u| u.public_key }

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
    # num_users<Integer> total number of users
    # num_system_users<Integer> number of preserved system keys
    # policy<LoginPolicy> the effective login policy
    #
    # === Return
    # description<String>
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
  end 

end