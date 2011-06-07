#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  module MetadataWriters

    # Dictionary writer.
    class DictionaryMetadataWriter < MetadataWriter

      # File extension for bash output
      def file_extension; '.dict'; end

      protected

      # Write given metadata to a bash file.
      #
      # === Parameters
      # file_name_prefix(String):: name prefix for generated file
      # metadata(Hash):: Hash-like metadata to write
      # subpath(Array|String):: subpath or nil
      #
      # === Return
      # always true
      def write_file(file_name_prefix, metadata, subpath = nil)
        return super(file_name_prefix, metadata, subpath) unless metadata.respond_to?(:has_key?)
        File.open(full_path(file_name_prefix, subpath), "w") do |f|
          metadata.each { |k, v| f.puts "#{k}=#{v}" }
        end
        true
      end

    end  # DictionaryMetadataWriter

  end  # MetadataWriters

end  # RightScale
