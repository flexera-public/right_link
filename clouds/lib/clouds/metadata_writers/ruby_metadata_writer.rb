#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  module MetadataWriters

    # Ruby script writer
    class RubyMetadataWriter < MetadataWriter

      attr_accessor :generation_command

      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for ruby files or nil
      def initialize(options)
        # defaults
        options = options.dup
        options[:file_extension] ||= '.rb'

        # super
        super(options)

        # local options.
        @generation_command = options[:generation_command]
      end

      protected

      RUBY_HEADER = ['# Warning: this file has been auto-generated',
                     '# any modifications can be overwritten']

      # Write given metadata to a ruby file.
      #
      # === Parameters
      # file_name_prefix(String):: name prefix for generated file
      # metadata(Hash):: Hash-like metadata to write
      # subpath(Array|String):: subpath or nil
      #
      # === Return
      # always true
      def write_file(metadata, subpath)
        return super(metadata, subpath) unless metadata.respond_to?(:has_key?)

        # write the cached file variant if the code-generation command line was passed.
        env_file_naem = @generation_command ? "#{@file_name_prefix}-cache" : @file_name_prefix
        env_file_path = create_full_path(env_file_naem, subpath)
        File.open(env_file_path, "w") do |f|
          f.puts RUBY_HEADER
          metadata.each do |k, v|
            # escape backslashes and single quotes.
            v = v.gsub(/\\|'/) { |c| "\\#{c}" }
            f.puts "ENV['#{k}']='#{v}'"
          end
        end
 
        # write the generation command, if given.
        if @generation_command
          File.open(create_full_path(@file_name_prefix, subpath), "w") do |f|
            f.puts RUBY_HEADER
            f.puts "raise 'ERROR: unable to fetch metadata' unless system(\"#{@generation_command}\")"
            f.puts "require '#{env_file_path}'"
          end
        end
        true
      end

    end  # RubyMetadataWriter

  end  # MetadataWriters

end  # RightScale
