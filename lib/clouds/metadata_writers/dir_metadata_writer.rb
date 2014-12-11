#
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats
require 'fileutils'

module RightScale

  module MetadataWriters

    # Structured directory writer
    class DirMetadataWriter < MetadataWriter
      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for dictionary files or nil
      def initialize(options)
        # defaults
        options = options.dup
        @formatter = DirMetadataFormatter.new(options)
        # super
        super(options)
      end

      protected

      # Write given metadata to a dictionary file.
      #
      # === Parameters
      # metadata(Hash):: Hash-like metadata to write
      # subpath(Array|String):: subpath or nil
      #
      # === Return
      # always true
      def write_file(metadata)
        return unless @formatter.can_format?(metadata)
        flat_metadata = @formatter.format(metadata)
        flat_metadata.each do |file, value|
          leaf = File.join(@file_name_prefix, file)
          File.open(create_full_path(leaf), "w", DEFAULT_FILE_MODE) do |f|
            f.puts value
          end
        end
        true
      end

    end  # RawMetadataWriter

  end  # MetadataWriters

end  # RightScale

