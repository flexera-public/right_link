#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

require 'fileutils'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'shell_utilities'))

begin
  require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'platform'))
  output_dir = File.join(RightScale::Platform.filesystem.spool_dir, 'ec2')
rescue Exception => e
  STDERR.puts "!!!!! FAILED TO DISCOVER EC2 USERDATA OUTPUT DIR"
  STDERR.puts "!!!!! Error: #{e}"
  STDERR.puts e.backtrace.join("\n")
  exit 1
end

OUTPUT_DIR    = output_dir
USER_PREFX    = File.join(OUTPUT_DIR, 'user-data')
SHEBANG_REGEX = /^#!/

module RightScale
  class UserDataWriter

    # Write given user data to files
    # May cause process to exit with code 1 in case of failure
    #
    # === Parameters
    # data(String):: Query string like or inline script user data
    #
    # === Return
    # true:: Always return true
    def self.write(data)
      FileUtils.mkdir_p OUTPUT_DIR
      begin
        File.open("#{USER_PREFX}.raw", "w") { |f| f.write data }
        if data =~ SHEBANG_REGEX
          handle_shebang_userdata(data)
        else
          handle_querystring_userdata(data)
        end
      rescue Exception => e
        STDERR.puts "!!!!! FAILED TO PROCESS EC2 USER DATA"
        STDERR.puts "!!!!! Error: #{e}"
        STDERR.puts e.backtrace.join("\n")
        exit 1
      end
      true
    end

    protected

    # Process inline script user data
    #
    # === Parameters
    # data(String):: Inline script user data
    #
    # === Return
    # true:: Always return true
    def self.handle_shebang_userdata(data)
      hash = {}

      File.open(File.join(OUTPUT_DIR, 'user-data.txt')) do |f|
        lines = f.readlines
        lines = lines.map { |l| l.chomp }
        lines.each do |line|
          name, value = line.split(/=/, 2)
          hash[name] = value
        end
      end

      write_userdata(hash, false)
    end

    # Process query string like user data
    #
    # === Parameters
    # data(String):: Query string user data
    #
    # === Return
    # true:: Always return true
    def self.handle_querystring_userdata(data)
      hash = {}

      data.split('&').each do |pair|
        name, value = pair.split(/=/, 2)
        hash[name] = value
      end

      write_userdata(hash, true)
    end

    # Write user data to shell and ruby scripts and optionally to text file
    #
    # === Parameters
    # hash(Hash):: Hash of user data keyed by name
    # include_txt(TrueClass|FalseClass):: Generate user data text file if true
    #
    # === Return
    # true:: Always return true
    def self.write_userdata(hash, include_txt)
      bash = File.open(File.join(OUTPUT_DIR, 'user-data.sh'),'w')
      ruby = File.open(File.join(OUTPUT_DIR, 'user-data.rb'),'w')
      text = File.open(File.join(OUTPUT_DIR, 'user-data.txt'), 'w') if include_txt

      hash.each_pair do |name, value|
        env_name = name.gsub(/\W/, '_')
        env_name_upcase = name.gsub(/\W/, '_').upcase
        env_name = 'EC2_' + env_name unless env_name =~ /^(RS_|EC2_)/ # hack
        bash.puts "export #{env_name_upcase}=\"#{ShellUtilities::escape_shell_source_string(value)}\""
        ruby.puts "ENV['#{env_name_upcase}']='#{ShellUtilities::escape_ruby_source_string(value)}'"
        text.puts "#{env_name}=#{value}" if text
      end

      bash.close
      ruby.close
      text.close if text
      true
    end

  end
end
