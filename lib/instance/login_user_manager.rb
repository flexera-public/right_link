module RightScale
  class LoginUserManager
    include Singleton

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

    def pick_username(preference, blacklist=nil)
      if blacklist.nil? || !blacklist.include?(preference)
        username = preference
      else
        i = 1
        i += 1 while blacklist.include?("#{preference}_#{i}")
        username = "preference_#{i}"
      end

      username
    end

    def setup_profile(username, home_dir, custom_data, force)
      return false if custom_data.nil? || custom_data.empty?

      checksum_path = File.join('.rightscale', PROFILE_CHECKSUM)
      return false if !force && File.exists?(File.join(home_dir, checksum_path))

      t0 = Time.now.to_i
      STDOUT.puts "Performing profile setup for #{username}..."

      tmpdir = Dir.mktmpdir
      file_path = File.join(tmpdir, File.basename(custom_data))
      if download_files(custom_data, file_path) && extract_files(username, file_path, home_dir)
        save_checksum(username, file_path, checksum_path, home_dir)
        t1 = Time.now.to_i
        STDOUT.puts "Setup complete (#{t1 - t0} sec)" if t1 - t0 >= 2
      end

      return true
    rescue Exception => e
      STDERR.puts "Failed to create profile for #{username}; continuing"
      STDERR.puts "#{e.class.name}: #{e.message} - #{e.backtrace.first}"
      Log.error("#{e.class.name}: #{e.message} - #{e.backtrace.first}")
      return false
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir && File.exists?(tmpdir)
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