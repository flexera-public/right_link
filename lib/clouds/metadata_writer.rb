#
# Copyright (c) 2010 by RightScale Inc., all rights reserved
#
# Write given user data to files in /var/spool/ec2 in text, shell and ruby
# script formats

module RightScale

  # Base implementation for a metadata writer. By default writes a raw
  # metadata format.
  class MetadataWriter
    DEFAULT_FILE_MODE = 0640

    attr_accessor :file_extension, :file_name_prefix, :output_dir_path

    # Initializer
    #
    # === Parameters
    # options[:file_extension](String):: output file extension
    # options[:file_name_prefix](String):: output file name sans extension
    # options[:output_dir_path](String):: output directory, defaults to RS spool dir
    # options[:read_override](Proc(reader, subpath):: read override or nil
    # options[:write_override](Proc(writer, metadata subpath):: write override or nil
    #
    # === Return
    # always true
    def initialize(options)
      raise ArgumentError.new("options[:file_name_prefix] is required") unless @file_name_prefix = options[:file_name_prefix]
      raise ArgumentError.new("options[:output_dir_path] is required") unless @output_dir_path = options[:output_dir_path]
      @file_extension = options[:file_extension] || '.raw'
      @read_override = options[:read_override]
      @write_override = options[:write_override]
    end

    # Reads metadata from file.
    #
    # === Parameters
    # subpath(Array|String):: subpath or nil
    #
    # === Return
    # result(String):: contents of generated file
    def read(subpath = nil)
      return @read_override.call(self, subpath) if @read_override
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
      return @write_override.call(self, metadata, subpath) if @write_override
      return write_file(metadata, subpath)
    end

    # Escapes double-quotes (and literal backslashes since they are escape
    # characters) in the given string.
    def self.escape_double_quotes(value)
      return value.to_s.gsub(/\\|"/) { |c| "\\#{c}" }
    end

    # Escapes single-quotes (and literal backslashes since they are escape
    # characters) in the given string.
    def self.escape_single_quotes(value)
      return value.to_s.gsub(/\\|'/) { |c| "\\#{c}" }
    end

    # Determines the first line of text (or the only line) for the given value.
    #
    # === Parameters
    # value(Object):: any value
    #
    # === Return
    # result(String):: first line or empty
    def self.first_line_of(value)
      # flatten any value which supports it
      value = value.flatten if value.respond_to?(:flatten)

      # note that the active_support gem redefines String.first from being the
      # same as .lines.first to returning the .first(n=1) characters.
      if value.respond_to?(:lines)
        value = value.lines.first
      elsif value.respond_to?(:first)
        value = value.first
      end
      return value.to_s.strip
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
      File.open(create_full_path(@file_name_prefix, subpath), "w", DEFAULT_FILE_MODE) { |f| f.write(metadata.to_s) }
    end

  end  # MetadataWriter

end  # RightScale
