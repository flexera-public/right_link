#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

require 'fileutils'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'lib', 'shell_utilities'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'platform'))

SHEBANG_REGEX = /^#!/

module RightScale
  class UserDataWriter

    # Create a new userdata writer.
    #
    # === Parameters
    # output_subdir(String):: Name of subdirectory under platform spool dir where files will be written
    # ec2_name_hack(true|false):: Optional; prefix variables with EC2_ unless they already begin with EC2_ or RS_
    #
    # === Return
    # true:: Always return true
    def initialize(output_subdir, ec2_name_hack=false)
      @output_dir    = File.join(RightScale::Platform.filesystem.spool_dir, output_subdir)
      @user_prefx    = File.join(@output_dir, 'user-data')
      @ec2_name_hack = ec2_name_hack
    end

    # Write given user data to files.
    #
    # === Parameters
    # data(String|Hash):: Query string like or inline script user data
    #
    # === Return
    # true:: Always return true
    def write(data)
      FileUtils.mkdir_p @output_dir

      if data.kind_of?(Hash)
        write_userdata(data)
      elsif data =~ SHEBANG_REGEX
        handle_shebang_userdata(data)
      else
        handle_querystring_userdata(data)
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
    def handle_shebang_userdata(data)
      hash = {}

      File.open(File.join(@output_dir, 'user-data.txt')) do |f|
        lines = f.readlines
        lines = lines.map { |l| l.chomp }
        lines.each do |line|
          name, value = line.split(/=/, 2)
          hash[name] = value
        end
      end

      write_userdata(hash)
    end

    # Process query string like user data
    #
    # === Parameters
    # data(String):: Query string user data
    #
    # === Return
    # true:: Always return true
    def handle_querystring_userdata(data)
      hash = {}

      data.split('&').each do |pair|
        name, value = pair.split(/=/, 2)
        hash[name] = value
      end

      File.open("#{@user_prefx}.raw", "w") { |f| f.write data }
      write_userdata(hash)
    end

    # Write user data to shell script and ruby script. Both output files are
    # suitable for sourcing/loading into a parent script which will then have
    # access to all userdata as environment variables.
    #
    # === Parameters
    # hash(Hash):: Hash of user data keyed by name
    #
    # === Return
    # true:: Always return true
    def write_userdata(hash)
      bash = File.open(File.join(@output_dir, 'user-data.sh'),'w')
      ruby = File.open(File.join(@output_dir, 'user-data.rb'),'w')
      dict  = File.open(File.join(@output_dir, 'user-data.dict'),'w')

      hash.each_pair do |name, value|
        env_name = name.gsub(/\W/, '_').upcase
        env_name = 'EC2_' + env_name if @ec2_name_hack && (env_name !~ /^(RS_|EC2_)/)
        bash.puts "export #{env_name}=\"#{ShellUtilities::escape_shell_source_string(value)}\""
        ruby.puts "ENV['#{env_name}']='#{ShellUtilities::escape_ruby_source_string(value)}'"
        dict.puts  "#{env_name}=#{value}"
      end

      bash.close
      ruby.close
      dict.close      
      true
    end

  end
end
