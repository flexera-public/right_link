#
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  module MetadataWriters

    # Dictionary (key=value pairs) writer.
    class RawMetadataWriter < MetadataWriter

      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for dictionary files or nil
      def initialize(options)
        # defaults
        options = options.dup
        options[:file_extension] ||= '.raw'

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
        return unless metadata.kind_of?(String)

        File.open(create_full_path(@file_name_prefix), "w", DEFAULT_FILE_MODE) do |f|
          f.puts metadata
        end
        true
      end

    end  # RawMetadataWriter

  end  # MetadataWriters

end  # RightScale
