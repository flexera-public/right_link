module GemUtilities
  GEM_FILE_GLOB_PATTERN  = '*.gem'
  GEM_FILE_REGEX_PATTERN = /(\d)+_([0-9a-z\-\_]+)-([0-9.]+)(-[0-9a-z]+)*.gem/i

  # Install gems
  #
  # === Parameters
  # gem_dirs(Array):: Paths to platform-specific gems, relative to PWD
  # gem_command(String):: Shell command to use when invoking "gem" binary
  # idempotent(Boolean):: true if only to install non-existent packages, otherwise always install all
  #
  # === Return
  # public_token(String):: Public token
  def self.install(gem_dirs, gem_command, output_io, idempotent)
    all_packages = gem_dirs.inject([]) { |a, d| a + Dir.glob(File.join(d, GEM_FILE_GLOB_PATTERN)) }
    all_packages.sort! { |a, b| File.basename(a) <=> File.basename(b) }

    if idempotent
      output_io.puts "Determining gems to install..."
      
      install_packages = []
      all_packages.each do |gem_file|
        basename    = File.basename(gem_file)
        pat         = GEM_FILE_REGEX_PATTERN.match(basename)

        if !pat || !Gem.available?(pat[2], "= #{pat[3]}")
          install_packages << gem_file
        end
      end

      output_io.puts "#{install_packages.size} new gems to install"
    else
      install_packages = all_packages
    end
    
    if install_packages.size > 0
      output_io.puts `#{gem_command} install --force --ignore-dependencies --no-rdoc --no-ri #{install_packages.join(' ')}`
      fail("Gem installation failed, exit code #{$?.to_i}") unless $?.success?
    end
  end
end