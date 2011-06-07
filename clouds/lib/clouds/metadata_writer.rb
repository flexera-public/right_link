#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  # Base implementation for a metadata writer. By default writes a raw
  # metadata format.
  class MetadataWriter

    attr_accessor :file_name_prefix, :output_dir_path

    # Initializer
    #
    # === Parameters
    # options[:output_dir_path](String):: output directory, defaults to RS spool dir
    #
    # === Return
    # always true
    def initialize(options)
      raise ArgumentError.new("options[:file_name_prefix] is required") unless @file_name_prefix = options[:file_name_prefix]
      raise ArgumentError.new("options[:file_name_prefix] is required") unless @output_dir_path = options[:output_dir_path]
    end

    # Output file extension for this writer type (defaults to .raw)
    def file_extension; '.raw'; end

    # Reads metadata from file.
    #
    # === Parameters
    # subpath(Array|String):: subpath or nil
    #
    # === Return
    # result(String):: contents of generated file
    def read(subpath = nil)
      return read_file(@file_name_prefix, subpath)
    end

    # Writes given metadata to file.
    #
    # === Parameters
    # metadata(Hash):: Hash-like metadata
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # always true
    def write(metadata, subpath = nil)
      FileUtils.mkdir_p(@output_dir_path)
      return write_file(@file_name_prefix, metadata, subpath)
    end

    protected

    # Full path of generated file.
    #
    # === Parameters
    # file_name_prefix(String):: name prefix for generated file
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # result(String):: full path of generated file
    def full_path(file_name_prefix, subpath = nil)
      if subpath
        # legacy ec2 support omits file extension and creates a parent dir
        # using file name prefix; this is the default behavior.
        subpath = subpath.join('-') if subpath.kind_of?(Array)
        subpath = subpath.gsub("\\", '-').gsub('/', '-').chomp('-')
        full_path = File.join(@output_dir_path, file_name_prefix, subpath)
      else
        full_path = File.join(@output_dir_path, "#{file_name_prefix}#{file_extension}")
      end
      return File.normalize_path(full_path)
    end

    # Reads metadata from file.
    #
    # === Parameters
    # file_name_prefix(String):: name prefix for generated file
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # result(String):: contents of generated file
    def read_file(file_name_prefix, subpath)
      return File.read(full_path(file_name_prefix, subpath))
    end

    # Writes given metadata to file.
    #
    # === Parameters
    # file_name_prefix(String):: name prefix for generated file
    # metadata(Hash):: Hash-like metadata to write
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # always true
    def write_file(file_name_prefix, metadata, subpath)
      File.open(full_path(file_name_prefix, subpath), "w") { |f| f.write(metadata.to_s) }
    end

  end  # MetadataWriter

end  # RightScale
