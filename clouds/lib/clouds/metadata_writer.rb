#!/opt/rightscale/sandbox/bin/ruby
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby 
# script formats

module RightScale

  # Base implementation for a metadata writer. By default writes a raw
  # metadata format.
  class MetadataWriter

    attr_accessor :file_extension, :file_name_prefix, :output_dir_path

    # Initializer
    #
    # === Parameters
    # options[:output_dir_path](String):: output directory, defaults to RS spool dir
    #
    # === Return
    # always true
    def initialize(options)
      raise ArgumentError.new("options[:file_name_prefix] is required") unless @file_name_prefix = options[:file_name_prefix]
      raise ArgumentError.new("options[:output_dir_path] is required") unless @output_dir_path = options[:output_dir_path]
      @file_extension = options[:file_extension] || '.raw'
      @read_file_override = options[:read_file_override]
      @write_file_override = options[:write_file_override]
    end

    # Reads metadata from file.
    #
    # === Parameters
    # subpath(Array|String):: subpath or nil
    #
    # === Return
    # result(String):: contents of generated file
    def read(subpath = nil)
      return @read_file_override.call(self, subpath) if @read_file_override
      return read_file(subpath)
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
      return @write_file_override.call(self, metadata, subpath) if @write_file_override
      return write_file(metadata, subpath)
    end

    protected

    # Full path of generated file.
    #
    # === Parameters
    # file_name(String):: output file name without extension
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # result(String):: full path of generated file
    def full_path(file_name, subpath = nil)
      if subpath
        # legacy ec2 support omits file extension and creates a parent dir
        # using file name prefix; this is the default behavior.
        subpath = subpath.join('-') if subpath.kind_of?(Array)
        subpath = subpath.gsub(/[\/\\]+/, '-').gsub(/^-+|-+$/, '')
        return File.normalize_path(File.join(@output_dir_path, file_name, subpath)) unless subpath.empty?
      end

      return File.normalize_path(File.join(@output_dir_path, "#{file_name}#{@file_extension}"))
    end

    # Creates the parent directory for the full path of generated file.
    #
    # === Parameters
    # file_name(String):: output file name without extension
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # result(String):: full path of generated file
    def create_full_path(file_name, subpath = nil)
      path = full_path(file_name, subpath)
      FileUtils.mkdir_p(File.dirname(path))
      path
    end

    # Reads metadata from file.
    #
    # === Parameters
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # result(String):: contents of generated file or empty
    def read_file(subpath)
      path = full_path(@file_name_prefix, subpath)
      return File.file?(path) ? File.read(path) : ''
    end

    # Writes given metadata to file.
    #
    # === Parameters
    # metadata(Hash):: Hash-like metadata to write
    # subpath(Array|String):: subpath if deeper than root or nil
    #
    # === Return
    # always true
    def write_file(metadata, subpath)
      File.open(create_full_path(@file_name_prefix, subpath), "w") { |f| f.write(metadata.to_s) }
    end

  end  # MetadataWriter

end  # RightScale
