#
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

require 'json'

module RightScale

  module MetadataWriters

    class JsonMetadataWriter < MetadataWriter

      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for dictionary files or nil
      def initialize(options)
        # defaults
        options = options.dup
        options[:file_extension] ||= '.json'
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
        return unless metadata.respond_to?(:has_key?)
        File.open(create_full_path(@file_name_prefix), "w", DEFAULT_FILE_MODE) do |f|
          f.print(metadata.to_json)
        end
      end

    end  # JsonMetadataWriter

  end  # MetadataWriters

end  # RightScale
