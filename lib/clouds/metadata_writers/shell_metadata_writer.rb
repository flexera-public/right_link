#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  module MetadataWriters

    # Shell script writer.
    class ShellMetadataWriter < MetadataWriter

      attr_accessor :generation_command

      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for shell files or nil
      def initialize(options)
        # defaults
        options = options.dup
        default_file_extension = RightScale::Platform.windows? ? '.bat' : '.sh'
        options[:file_extension] ||= default_file_extension
        @generation_command = options[:generation_command]

        # super
        super(options)
      end

      protected

      if RightScale::Platform.windows?

        WINDOWS_SHELL_HEADER = ['@echo off',
                                'rem # Warning: this file has been auto-generated',
                                'rem # any modifications can be overwritten']

        # Write given metadata to a bash file.
        #
        # === Parameters
        # metadata(Hash):: Hash-like metadata to write
        # subpath(Array|String):: subpath or nil
        #
        # === Return
        # always true
        def write_file(metadata, subpath)
          return super(metadata, subpath) unless metadata.respond_to?(:has_key?)

          # write the cached file variant if the code-generation command line was passed.
          env_file_name = @generation_command ? "#{@file_name_prefix}-cache" : @file_name_prefix
          env_file_path = create_full_path(env_file_name, subpath)
          File.open(env_file_path, "w", DEFAULT_FILE_MODE) do |f|
            f.puts(WINDOWS_SHELL_HEADER)
            metadata.each do |k, v|
              # ensure value is a single line (multiple lines could be interpreted
              # as subsequent commands) by truncation since windows shell doesn't
              # have escape characters.
              v = self.class.first_line_of(v)
              f.puts "set #{k}=#{v}"
            end
          end

          # write the generation command, if given.
          if @generation_command
            File.open(create_full_path(@file_name_prefix, subpath), "w", DEFAULT_FILE_MODE) do |f|
              f.puts(WINDOWS_SHELL_HEADER)
              f.puts(@generation_command)
              f.puts("call \"#{env_file_path}\"")
            end
          end
          true
        end

      else  # not windows

        LINUX_SHELL_HEADER = ['#!/bin/bash',
                              '# Warning: this file has been auto-generated',
                              '# any modifications can be overwritten']

        # Write given metadata to a bash file.
        #
        # === Parameters
        # metadata(Hash):: Hash-like metadata to write
        # subpath(Array|String):: subpath or nil
        #
        # === Return
        # always true
        def write_file( metadata, subpath)
          return super(metadata, subpath) unless metadata.respond_to?(:has_key?)

          # write the cached file variant if the code-generation command line was passed.
          env_file_name = @generation_command ? "#{@file_name_prefix}-cache" : @file_name_prefix
          env_file_path = create_full_path(env_file_name, subpath)
          File.open(env_file_path, "w", DEFAULT_FILE_MODE) do |f|
            f.puts(LINUX_SHELL_HEADER)
            metadata.each do |k, v|
              # escape backslashes and double quotes.
              v = self.class.escape_double_quotes(v)
              f.puts "export #{k}=\"#{v}\""
            end
          end

          # write the generation command, if given.
          if @generation_command
            File.open(create_full_path(@file_name_prefix, subpath), "w", DEFAULT_FILE_MODE) do |f|
              f.puts(LINUX_SHELL_HEADER)
              f.puts(@generation_command)
              f.puts(". #{env_file_path}")
            end
          end
          true
        end

      end  # if windows

    end  # ShellMetadataWriter

  end  # MetadataWriters

end  # RightScale
