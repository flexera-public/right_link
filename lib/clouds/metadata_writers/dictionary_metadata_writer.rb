#
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  module MetadataWriters

    # Dictionary (key=value pairs) writer.
    class DictionaryMetadataWriter < MetadataWriter

      # Initializer.
      #
      # === Parameters
      # options[:file_extension](String):: dotted extension for dictionary files or nil
      def initialize(options)
        # defaults
        options = options.dup
        options[:file_extension] ||= '.dict'

        # super
        super(options)
      end

      protected

      # Read a dictionary file on disk and parse into key/value pairs.
      #
      # === Parameters
      # subpath(Array|String):: subpath or nil
      #
      # === Return
      # result(Hash):: dictionary of metadata
      def read_file(subpath = nil)
        result = {}
        path = full_path(@file_name_prefix, subpath)
        contents = File.file?(path) ? File.read(path) : ''
        contents.each_line do |line|
          match = line.chomp.match(/^(.+)=(.*)$/)
          result[match[1]] = match[2]
        end
        result
      end

      # Write given metadata to a dictionary file.
      #
      # === Parameters
      # metadata(Hash):: Hash-like metadata to write
      # subpath(Array|String):: subpath or nil
      #
      # === Return
      # always true
      def write_file(metadata, subpath = nil)
        return super(metadata, subpath) unless metadata.respond_to?(:has_key?)
        File.open(create_full_path(@file_name_prefix, subpath), "w", DEFAULT_FILE_MODE) do |f|
          metadata.each do |k, v|
            # ensure value is a single line by truncation since most
            # dictionary format parsers expect literal chars on a single line.
            v = self.class.first_line_of(v)
            f.puts "#{k}=#{v}"
          end
        end
        true
      end

    end  # DictionaryMetadataWriter

  end  # MetadataWriters

end  # RightScale
