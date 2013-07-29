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
  class LoginUserManager
    include RightSupport::Ruby::EasySingleton

    PROFILE_CHECKSUM = "profile.md5"

    MIN_UID  = 10_000
    MAX_UID  = 2**32 - 1
    MAX_UUID = MAX_UID - MIN_UID

    # List of directories that commonly contain user and group management utilities
    SBIN_PATHS = ['/usr/bin', '/usr/sbin', '/bin', '/sbin']

    # List of viable default shells. Useful because Ubuntu's adduser seems to require a -s parameter.
    DEFAULT_SHELLS = ['/bin/bash', '/usr/bin/bash', '/bin/sh', '/usr/bin/sh', '/bin/dash', '/bin/tcsh']

    # Map a universally-unique integer RightScale user ID to a locally-unique Unix UID.
    def uuid_to_uid(uuid)
      uuid = Integer(uuid)
      if uuid >= 0 && uuid <= MAX_UUID
        10_000 + uuid
      else
        raise RangeError, "#{uuid} is not within (0..#{MAX_UUID})"
      end
    end

    # Pick a username that does not yet exist on the system. If the given
    # username does not exist, it is returned; else we add a "_1" suffix
    # and continue incrementing the number until we arrive at a username
    # that does not yet exist.
    #
    # === Parameters
    # ideal(String):: the user's ideal (chosen) username
    #
    # === Return
    # username(String):: username with possible postfix
    def pick_username(ideal)
      name = ideal
      i = 0

      while user_exists?(name)
        i += 1
        name = "#{ideal}_#{i}"
      end

      name
    end

    # Ensure that a given user exists and that his group membership is correct.
    #
    # === Parameters
    # username(String):: preferred username of RightScale user
    # uuid(String):: RightScale user's UUID
    # superuser(Boolean):: whether the user should have sudo privileges
    #
    # === Block
    # If a block is given AND the user needs to be created, yields to the block
    # with the to-be-created account's username, before creating it. This gives
    # the caller a chance to provide interactive feedback to the user.
    #
    # === Return
    # username(String):: user's actual username (may vary from preferred username)
    #
    # === Raise
    # (LoginManager::SystemConflict):: if an existing non-RightScale-managed UID prevents us from creating a user
    def create_user(username, uuid, superuser)
      uid = LoginUserManager.uuid_to_uid(uuid)

      if uid_exists?(uid, ['rightscale'])
        username = uid_to_username(uid)
      elsif !uid_exists?(uid)
        username  = pick_username(username)
        yield(username) if block_given?
        add_user(username, uid)
        modify_group('rightscale', :add, username)

        # NB it is SUPER IMPORTANT to pass :force=>true here. Due to an oddity in Ruby's Etc
        # extension, a user who has recently been added, won't seem to be a member of
        # any groups until the SECOND time we enumerate his group membership.
        manage_user(uuid, superuser, :force=>true)
      else
        raise RightScale::LoginManager::SystemConflict, "A user with UID #{uid} already exists and is " +
                                                        "not managed by RightScale"
      end

      username
    end

    # If the given user exists and is RightScale-managed, then ensure his login information and
    # group membership are correct. If force == true, then management tasks are performed
    # irrespective of the user's group membership status.
    #
    # === Parameters
    # uuid(String):: RightScale user's UUID
    # superuser(Boolean):: whether the user should have sudo privileges
    # force(Boolean):: if true, performs group management even if the user does NOT belong to 'rightscale'
    #
    # === Options
    # :force:: if true, then the user will be updated even if they do not belong to the RightScale group
    # :disable:: if true, then the user will be prevented from logging in
    #
    # === Return
    # username(String):: if the user exists, returns his actual username
    # false:: if the user does not exist
    def manage_user(uuid, superuser, options={})
      uid      = LoginUserManager.uuid_to_uid(uuid)
      username = uid_to_username(uid)
      force    = options[:force] || false
      disable  = options[:disable] || false

      if ( force && uid_exists?(uid) ) || uid_exists?(uid, ['rightscale'])
        modify_user(username, disable)
        action = superuser ? :add : :remove
        modify_group('rightscale_sudo', action, username) if group_exists?('rightscale_sudo')

        username
      else
        false
      end
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


    def random_password
      letters =  [('a'..'z'),('A'..'Z')].map{|i| i.to_a}.flatten
      password = (0..32).map{ letters[rand(letters.length)] }.join
      Shellwords.escape(password.crypt("rightscale"))
    end

    # Create a Unix user with the "useradd" command.
    #
    # === Parameters
    # username(String):: username
    # uid(String):: account's UID
    # expired_at(Time):: account's expiration date; default nil
    # shell(String):: account's login shell; default nil (use systemwide default)
    #
    #
    # === Raise
    # (RightScale::LoginManager::SystemConflict):: if the user could not be created for some reason
    #
    # === Return
    # true:: always returns true
    def add_user(username, uid, shell=nil)
      uid = Integer(uid)
      shell ||= DEFAULT_SHELLS.detect { |sh| File.exists?(sh) }

      useradd = find_sbin('useradd')

      unless shell.nil?
        dash_s = "-s #{Shellwords.escape(shell)}"
      end

      result = sudo("#{useradd} #{dash_s} -u #{uid} -p #{random_password} -m #{Shellwords.escape(username)}")

      case result.exitstatus
      when 0
        home_dir = Shellwords.escape(Etc.getpwnam(username).dir)

        sudo("chmod 0771 #{Shellwords.escape(home_dir)}")
        # Locking account to prevent warning os SUSE(it complains on unlocking non-locked account)
        modify_user(username, true, shell)

        RightScale::Log.info "LoginUserManager created #{username} successfully"
      else
        raise RightScale::LoginManager::SystemConflict, "Failed to create user #{username}"
      end

      true
    end

    # Modify a user with the "usermod" command.
    #
    # === Parameters
    # username(String):: username
    # uid(String):: account's UID
    # locked(true,false):: if true, prevent the user from logging in
    # shell(String):: account's login shell; default nil (use systemwide default)
    #
    # === Return
    # true:: always returns true
    def modify_user(username, locked=false, shell=nil)
      shell ||= DEFAULT_SHELLS.detect { |sh| File.exists?(sh) }

      usermod = find_sbin('usermod')

      if locked
        # the man page claims that "1" works here, but testing proves that it doesn't.
        # use 1970 instead.
        dash_e = "-e 1970-01-01 -L"
      else
        dash_e = "-e 99999 -U"
      end

      unless shell.nil?
        dash_s = "-s #{Shellwords.escape(shell)}"
      end

      result = sudo("#{usermod} #{dash_e} #{dash_s} #{Shellwords.escape(username)}")

      case result.exitstatus
      when 0
        RightScale::Log.info "LoginUserManager modified #{username} successfully"
      else
        RightScale::Log.error "Failed to modify user #{username}"
      end

      true
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
    def modify_group(group, operation, username)
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

      usermod = find_sbin('usermod')

      result = sudo("#{usermod} -G #{groups} #{username}")

      case result.exitstatus
      when 0
        RightScale::Log.info "Successfully performed group-#{operation} of #{username} to #{group}"
        return true
      else
        RightScale::Log.error "Failed group-#{operation} of #{username} to #{group}"
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
    # exist_status(Boolean):: true if exists; otherwise false
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

    # Check if group with specified name exists in the system.
    #
    # === Parameters
    # name(String):: group's name
    #
    # === Block
    # If a block is given, it will be yielded to with various status messages
    # suitable for display to the user.
    #
    # === Return
    # exist_status(Boolean):: true if exists; otherwise false
    def group_exists?(name)
      groups = Set.new
      Etc.group { |g| groups << g.name }
      groups.include?(name)
    end

    def setup_profile(username, home_dir, custom_data, force)
      return false if custom_data.nil? || custom_data.empty?

      checksum_path = File.join('.rightscale', PROFILE_CHECKSUM)
      return false if !force && File.exists?(File.join(home_dir, checksum_path))

      t0 = Time.now.to_i
      yield("Performing profile setup for #{username}...") if block_given?

      tmpdir = Dir.mktmpdir
      file_path = File.join(tmpdir, File.basename(custom_data))
      if download_files(custom_data, file_path) && extract_files(username, file_path, home_dir)
        save_checksum(username, file_path, checksum_path, home_dir)
        t1 = Time.now.to_i
        yield("Setup complete (#{t1 - t0} sec)") if block_given? && (t1 - t0 >= 2)
      end

      return true
    rescue Exception => e
      yield("Failed to create profile for #{username}; continuing") if block_given?
      yield("#{e.class.name}: #{e.message} - #{e.backtrace.first}") if block_given?
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
      return false
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir && File.exists?(tmpdir)
    end

    # Set some of the environment variables that would normally be set if a user
    # were to login to an interactive shell. This is useful when simulating an
    # interactive login, e.g. for purposes of running a user-specified command
    # via SSH.
    #
    # === Parameters
    # username(String):: user's name
    #
    # === Return
    # true:: always returns true
    def simulate_login(username)
      info = Etc.getpwnam(username)
      ENV['USER']  = info.name
      ENV['HOME']  = info.dir
      ENV['SHELL'] = info.shell
      true
    end

    protected

    # Run a command as root, jumping through a sudo gate if necessary.
    #
    # === Parameters
    # cmd(String):: the command to execute
    #
    # === Return
    # exitstatus(Process::Status):: the exitstatus of the process
    def sudo(cmd)
      cmd = "sudo #{cmd}" unless  Process.euid == 0

      RightScale::Log.info("LoginUserManager command: #{cmd}")
      output = %x(#{cmd})
      result = $?
      RightScale::Log.info("LoginUserManager result: #{$?.exitstatus}; output: #{cmd}")

      result
    end

    # Search through some directories to find the location of a binary. Necessary because different
    # Linux distributions put their user-management utilities in slightly different places.
    #
    # === Parameters
    # cmd(String):: name of command to search for, e.g. 'usermod'
    #
    # === Return
    # path(String):: the absolute path to the command
    #
    # === Raise
    # (LoginManager::SystemConflict):: if the command can't be found
    #
    def find_sbin(cmd)
      path = SBIN_PATHS.detect do |dir|
        File.exists?(File.join(dir, cmd))
      end

      raise RightScale::LoginManager::SystemConflict, "Failed to find a suitable implementation of '#{cmd}'." unless path

      File.join(path, cmd)
    end

    # Downloads a file from specified URL
    #
    # === Parameters
    # url(String):: URL to file
    # path(String):: downloaded file path
    #
    # === Return
    # downloaded(Boolean):: true if downloaded and saved successfully
    def download_files(url, path)
      client = RightSupport::Net::HTTPClient.new
      response = client.get(url, :timeout => 10)
      File.open(path, "wb") { |file| file.write(response) } unless response.empty?
      File.exists?(path)
    rescue Exception => e
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
      false
    end

    # Extracts an archive and moves files to destination directory
    # Supported archive types are:
    #   .tar.bz2 / .tbz
    #   .tar.gz / .tgz
    #   .zip
    #
    # === Parameters
    # username(String):: account's username
    # filename(String):: archive's path
    # destination_path(String):: path where extracted files should be
    # moved
    #
    # === Return
    # extracted(Boolean):: true if archive is extracted successfully
    def extract_files(username, filename, destination_path)
      escaped_filename = Shellwords.escape(filename)

      case filename
      when /(?:\.tar\.bz2|\.tbz)$/
        result = sudo("tar jxf #{escaped_filename} -C #{destination_path}")
      when /(?:\.tar\.gz|\.tgz)$/
        result = sudo("tar zxf #{escaped_filename} -C #{destination_path}")
      when /\.zip$/
        result = sudo("unzip -o #{escaped_filename} -d #{destination_path}")
      else
        raise ArgumentError, "Don't know how to extract #{filename}'"
      end

      extracted = result.success?
      chowned = change_owner(username, username, destination_path)

      extracted && chowned
    end

    # Calculates MD5 checksum for specified file and saves it
    #
    # === Parameters
    # username(String):: account's username
    # target(String):: path to file
    # checksum_path(String):: relative path to checksum file
    # destination(String):: path to file where checksum should be saved
    #
    # === Return
    # nil
    def save_checksum(username, target, checksum_path, destination)
      checksum = Digest::MD5.file(target).to_s

      temp_dir = File.join(File.dirname(target), File.dirname(checksum_path))
      temp_path = File.join(File.dirname(target), checksum_path)

      FileUtils.mkdir_p(temp_dir)
      FileUtils.chmod_R(0771, temp_dir) # need +x to others for File.exists? => true
      File.open(temp_path, "w") { |f| f.write(checksum) }

      change_owner(username, username, temp_dir)
      sudo("mv #{temp_dir} #{destination}")
    rescue Exception => e
      STDERR.puts "Failed to save checksum for #{username} profile"
      STDERR.puts "#{e.class.name}: #{e.message} - #{e.backtrace.first}"
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
    end

    # Changes owner of directories and files from given path
    #
    # === Parameters
    # username(String):: desired owner's username
    # group(String):: desired group name
    # path(String):: path for owner changing
    #
    # === Return
    # chowned(Boolean):: true if owner changed successfully
    def change_owner(username, group, path)
      result = sudo("chown -R #{Shellwords.escape(username)}:#{Shellwords.escape(group)} #{path}")

      result.success?
    end
  end
end
