#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  module MetadataWriters

    # Ruby writer
    class RubyMetadataWriter < MetadataWriter

      def initialize(options)
        # super
        super(options)

        # local options.
        @generation_command = options[:generation_command]
      end

      # File extension for bash output
      def file_extension; '.rb'; end

      protected

      # Write given metadata to a ruby file.
      #
      # === Parameters
      # file_name_prefix(String):: name prefix for generated file
      # metadata(Hash):: Hash-like metadata to write
      # subpath(Array|String):: subpath or nil
      #
      # === Return
      # always true
      def write_file(file_name_prefix, metadata, subpath)
        return super(file_name_prefix, metadata, subpath) unless metadata.respond_to?(:has_key?)

        # write the cached file variant if the code-generation command line was passed.
        env_file_name_prefix = @generation_command ? "#{file_name_prefix}-cache" : file_name_prefix
        env_file_path = full_path(env_file_name_prefix, subpath)
        File.open(env_file_path, "w") do |f|
          f.puts('# Warning: this file has been auto-generated')
          f.puts('# any modifications can be overwritten')
          metadata.each do |k, v|
            f.puts "ENV['#{k}']='#{ShellUtilities::escape_ruby_source_string(v)}'"
          end
        end

        # write the generation command, if given.
        if @generation_command
          File.open(full_path(file_name_prefix, subpath), "w") do |f|
            f.puts('# Warning: this file has been auto-generated')
            f.puts('# any modifications can be overwritten')
            f.puts "raise 'ERROR: unable to fetch metadata' unless system(\"#{@generation_command}\")"
            f.puts "require '#{env_file_path}'"
          end
        end
        true
      end

    end  # RubyMetadataWriter

  end  # MetadataWriters

end  # RightScale
