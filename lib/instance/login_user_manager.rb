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

    # Creates user account
    #
    # === Parameters
    # username(String):: username
    # uuid(String):: RightScale user's UUID
    # superuser(Boolean):: flag if user is superuser
    #
    # === Block
    # If a block is given AND the user needs to be created, yields to the block
    # with the to-be-created account's username, before creating it. This gives
    # the caller a chance to provide interactive feedback to the user.
    #
    # === Return
    # username(String):: created account's username
    def create_user(username, uuid, superuser)
      uid = LoginUserManager.uuid_to_uid(uuid)

      if uid_exists?(uid, ['rightscale'])
        username = uid_to_username(uid)
      elsif !uid_exists?(uid)
        username  = pick_username(username)
        yield(username) if block_given?
        add_user(username, uid)
        manage_group('rightscale', :add, username) if group_exists?('rightscale')
      else
        raise RightScale::LoginManager::SystemConflict, "A user with UID #{uid} already exists and is " +
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
      
      # Can't use executable? because the rightscale user can't execute useradd without sudo
      useradd = ['/usr/bin/useradd', '/usr/sbin/useradd', '/bin/useradd', '/sbin/useradd'].select { |key| File.exists? key }.first
      raise RightScale::LoginManager::SystemConflict, "Failed to find a suitable implementation of 'useradd'." unless useradd
      %x(sudo #{useradd} -s /bin/bash -u #{uid} -m #{Shellwords.escape(username)})

      case $?.exitstatus
      when 0
        home_dir = Shellwords.escape(Etc.getpwnam(username).dir)

        #FileUtils.chmod(0771, home_dir)
        %x(sudo chmod 0771 #{home_dir})

        RightScale::Log.info "User #{username} created successfully"
      else
        raise RightScale::LoginManager::SystemConflict, "Failed to create user #{username}"
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
      # Can't use executable? because the rightscale user can't execute usermod without sudo
      usermod = ['/usr/bin/usermod', '/usr/sbin/usermod', '/bin/usermod', '/sbin/usermod'].select { |key| File.exists? key }.first
      raise RightScale::LoginManager::SystemConflict, "Failed to find a suitable implementation of 'usermod'." unless usermod
      output = %x(sudo #{usermod} -G #{groups} #{username})

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
        %x(sudo tar jxf #{escaped_filename} -C #{destination_path})
      when /(?:\.tar\.gz|\.tgz)$/
        %x(sudo tar zxf #{escaped_filename} -C #{destination_path})
      when /\.zip$/
        %x(sudo unzip -o #{escaped_filename} -d #{destination_path})
      else
        raise ArgumentError, "Don't know how to extract #{filename}'"
      end
      extracted = $?.success?

      chowned = change_owner(username, username, destination_path)
      return extracted && chowned
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
      %x(sudo mv #{temp_dir} #{destination})
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
      %x(sudo chown -R #{Shellwords.escape(username)}:#{Shellwords.escape(group)} #{path})

      $?.success?
    end
  end
end
