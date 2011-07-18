#
# Copyright (c) 2011 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'extlib'

module RightScale

  # Abstract base class for all clouds.
  class Cloud

    # wildcard used for some 'all kinds' selections.
    WILDCARD = :*

    # default writer output file prefixes are based on EC2 legacy files.
    DEFAULT_CLOUD_METADATA_FILE_PREFIX = 'meta-data'
    DEFAULT_USER_METADATA_FILE_PREFIX = 'user-data'

    # raw metadata writer is a special case and normally only invoked while
    # metadata is being queried from source. it can also be referenced to read
    # back the metadata in raw form.
    RAW_METADATA_WRITER = :raw

    # exceptions
    class CloudError < Exception; end

    attr_reader :name, :script_path, :extended_clouds

    # Return type for any cloud action (e.g. write_metadata).
    class ActionResult
      attr_reader :error, :exitstatus, :output

      def initialize(options = {})
        @error = options[:error]
        @exitstatus = options[:exitstatus] || 0
        @output = options[:output]
      end
    end

    # Initializer.
    #
    # === Parameters
    # options(Hash):: options grab bag used to configure cloud and dependencies.
    def initialize(options)
      raise ArgumentError.new("options[:name] is required") unless @name = options[:name]
      raise ArgumentError.new("options[:script_path] is required") unless @script_path = options[:script_path]

      # break options lineage and use Mash to handle keys as strings or tokens.
      # note that this is not a deep copy as :ohai is an option representing the
      # full ohai node in at least one use case.
      @options = Mash.new(options)
      @extended_clouds = []
      default_option([:metadata_writers, :output_dir_path], File.join(RightScale::Platform.filesystem.spool_dir, 'cloud'))
      default_option([:cloud_metadata, :metadata_writers, :file_name_prefix], DEFAULT_CLOUD_METADATA_FILE_PREFIX)
      default_option([:user_metadata, :metadata_writers, :file_name_prefix], DEFAULT_USER_METADATA_FILE_PREFIX)
    end

    # Getter/setter for abbreviation which also sets default formatter options
    # when an abbreviation is set.
    def abbreviation(value = nil)
      unless value.to_s.empty?
        @abbreviation = value.to_s
        default_option([:cloud_metadata, :metadata_formatter, :formatted_path_prefix], "#{value.to_s.upcase}_")
      end
      @abbreviation
    end

    # Base paths for runtime cloud depedencies in order of priority. Defaults
    # to location of cloud module files.
    def dependency_base_paths(*args)
      @dependency_base_paths ||= []
      args.each do |path|
        path = relative_to_script_path(path)
        @dependency_base_paths << path unless @dependency_base_paths.include?(path)
      end
      @dependency_base_paths
    end

    # Runtime cloud depedencies (loaded on demand).
    def dependencies(*args)
      @dependencies ||= []
      args.each do |dependency_type|
        unless @dependencies.include?(dependency_type)
          # Just-in-time require new dependency
          resolve_dependency(dependency_type)
          @dependencies << dependency_type
        end
      end
      @dependencies
    end

    # Just-in-time requires a cloud's dependency, which should include its
    # relative location (and sub-type) in the dependency name
    # (e.g. 'metadata_sources/http_metadata_source' => Sources::HttpMetadataSource).
    # the dependency can also be in the RightScale module namespace because it
    # begin evaluated there.
    #
    # note that actual instantiation of the dependency is on-demand from the
    # cloud type.
    #
    # === Parameters
    # dependency_type(String|Token):: snake-case name for dependency type
    #
    # === Return
    # dependency(Class):: resolved dependency class
    def resolve_dependency(dependency_type)
      dependency_class_name = dependency_type.to_s.camelize
      begin
        dependency_class = Class.class_eval(dependency_class_name)
      rescue NameError
        search_paths = (dependency_base_paths || []) + [File.dirname(__FILE__)]
        dependency_file_name = dependency_type + ".rb"
        search_paths.each do |search_path|
          file_path = File.normalize_path(File.join(search_path, dependency_file_name))
          if File.file?(file_path)
            require File.normalize_path(File.join(search_path, dependency_type))
            break
          end
        end
        dependency_class = Class.class_eval(dependency_class_name)
      end
      dependency_class
    end

    # Defines a base cloud type which the current instance extends. The base
    # type is just-in-time evaluated into the current instance. The extended
    # cloud must have been registered successfully.
    #
    # === Parameters
    # cloud_name(String|Token): name of cloud to extend
    #
    # === Return
    # always true
    #
    # === Raise
    # UnknownCloud:: on failure to find extended cloud
    def extend_cloud(cloud_name)
      cloud_name = CloudFactory.normalize_cloud_name(cloud_name)
      unless @extended_clouds.include?(cloud_name)
        @extended_clouds << cloud_name
        script_path = CloudFactory.instance.registered_script_path(cloud_name)
        text = File.read(script_path)
        self.instance_eval(text)
      end
      true
    end

    # Base paths for external scripts which extend methods of cloud object.
    # Names of scripts become instance methods and can override the predefined
    # cloud methods. The factory defaults to using any scripts in
    # "<rs_root_path>/bin/<cloud alias(es)>" directories.
    def extension_script_base_paths(*args)
      @extension_script_base_paths ||= []
      args.each do |path|
        path = relative_to_script_path(path)
        @extension_script_base_paths << path unless @extension_script_base_paths.include?(path)
      end
      @extension_script_base_paths
    end

    # Dependency type for metadata formatter
    def metadata_formatter(type = nil)
      dependencies(type) if type
      @metadata_formatter ||= type || :metadata_formatter
    end

    # Dependency type for metadata provider
    def metadata_provider(type = nil)
      dependencies(type) if type
      @metadata_provider ||= type || :metadata_provider
    end

    # Dependency type for metadata source
    def metadata_source(type = nil)
      dependencies(type) if type
      @metadata_source ||= type || :metadata_source
    end

    # Dependency type for metadata tree climber
    def metadata_tree_climber(type = nil)
      dependencies(type) if type
      @metadata_tree_climber ||= type || :metadata_tree_climber
    end

    # Dependency type for metadata writers. Note that the raw writer is
    # automatic (writes raw responses using relative paths while data is being
    # queried).
    def metadata_writers(*args)
      dependencies(*args)
      @metadata_writers ||= []
      args.each { |metadata_writer| @metadata_writers << metadata_writer unless @metadata_writers.include?(metadata_writer) }
      @metadata_writers
    end

    # Determines if the current instance is running on the cloud indicated by
    # this object.
    #
    # === Return
    # result(Boolean):: true if current cloud, false otherwise
    def is_current_cloud?
      false  # clouds cannot self-detect without a specific implementation
    end

    # Updates the given node with any cloud-specific detailed information. Adds
    # nothing by default. The ohai node can be retreived as option(:ohai) and
    # any details can be added to the option(:ohai)[name] node.
    #
    # === Return
    # always true
    def update_details
      {}
    end

    # Convenience method for failing to load or execute cloud definition.
    #
    # === Parameters
    # message(String):: message
    #
    # === Raise
    # always CloudError
    def fail(message)
      raise CloudError.new(message)
    end

    # Convenience method for getting information about the current machine
    # platform.
    #
    # === Return
    # result(Boolean):: true if windows
    def platform
      ::RightScale::RightLinkConfig[:platform]
    end

    # Reads the generated metadata file of the given kind and writer type.
    #
    # === Parameters
    # kind(Symbol):: kind of metadata must be one of [:cloud_metadata, :user_metadata]
    # writer_type(Symbol):: writer_type [RAW_METADATA_WRITER, ...]
    #
    # === Return
    # result(ActionResult):: action result
    def read_metadata(kind = :user_metadata, writer_type = RAW_METADATA_WRITER, subpath = nil)
      kind = kind.to_sym
      writer_type = writer_type.to_sym
      if RAW_METADATA_WRITER == writer_type
        reader = raw_metadata_writer(kind)
      else
        reader = create_dependency_type(kind, :metadata_writers, writer_type)
      end
      output = reader.read(subpath)
      return ActionResult.new(:output => output)
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}")
    end

    # Queries and writes current metadata to file.
    #
    # === Parameters
    # kind(Symbol):: kind of metadata must be one of [:cloud_metadata, :user_metadata, WILDCARD]
    #
    # === Return
    # result(ActionResult):: action result
    def write_metadata(kind = WILDCARD)
      kind = kind.to_sym
      kinds = [:cloud_metadata, :user_metadata].select { |k| WILDCARD == kind || k == kind }
      kinds.each do |k|
        formatter = create_dependency_type(k, :metadata_formatter)
        writers = create_dependency_type(k, :metadata_writers, WILDCARD)
        metadata = build_metadata(k)
        unless metadata.empty?
          metadata = formatter.format_metadata(metadata)
          writers.each { |writer| writer.write(metadata) }
        end
      end
      return ActionResult.new
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}")
    ensure
      # release metadata source after querying all metadata.
      if @metadata_source_instance
        temp_metadata_source = @metadata_source_instance
        @metadata_source_instance = nil
        temp_metadata_source.finish
      end
    end

    # Convenience method for reading only cloud metdata.
    def read_cloud_metadata(writer_type = RAW_METADATA_WRITER, subpath = nil); read_metadata(:cloud_metadata, writer_type, subpath); end

    # Convenience method for reading only cloud metdata.
    def read_user_metadata(writer_type = RAW_METADATA_WRITER, subpath = nil); read_metadata(:user_metadata, writer_type, subpath); end

    # Convenience method for writing only cloud metdata.
    def write_cloud_metadata; write_metadata(:cloud_metadata); end

    # Convenience method for writing only user metdata.
    def write_user_metadata; write_metadata(:user_metadata); end

    # Attempts to clear any files generated by writers.
    #
    # === Return
    # always true
    #
    # === Raise
    # CloudError:: on failure to clean state
    def clear_state
      output_dir_paths = []
      [:cloud_metadata, :user_metadata].each do |k|
        writers = create_dependency_type(k, :metadata_writers, WILDCARD)
        writers << raw_metadata_writer(k)
        writers.each { |writer| output_dir_paths << writer.output_dir_path unless output_dir_paths.include?(writer.output_dir_path) }
      end
      last_exception = nil
      output_dir_paths.each do |output_dir_path|
        begin
          FileUtils.rm_rf(output_dir_path) if File.directory?(output_dir_path)
        rescue Exception => e
          last_exception = e
        end
      end
      fail(last_exception.message) if last_exception
      return ActionResult.new
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}")
    end

    # Executes a query for metadata and builds a metadata 'tree' according to
    # the rules of provider and tree climber.
    #
    # === Parameters
    # kind(Token):: must be one of [:cloud_metadata, :user_metadata]
    #
    # === Return
    # metadata(Hash):: Hash-like metadata response
    def build_metadata(kind)
      @metadata_source_instance = create_dependency_type(kind, :metadata_source) unless @metadata_source_instance
      metadata_tree_climber = create_dependency_type(kind, :metadata_tree_climber)
      provider = create_dependency_type(kind, :metadata_provider)
      provider.send(:metadata_source=, @metadata_source_instance)
      provider.send(:metadata_tree_climber=, metadata_tree_climber)
      provider.send(:raw_metadata_writer=, raw_metadata_writer(kind))

      # build
      return provider.send(:build_metadata)
    end

    # Gets the option given by path, if it exists.
    #
    # === Parameters
    # path(Array|String):: path to option as an array of path elements or single
    #  string which may contain forward slashes as element name delimiters.
    # default_value(String):: default value to conditionally insert/merge or nil
    #
    # === Return
    # result(Object):: existing option or nil
    def option(path)
      options = @options
      path = path.split('/') unless path.kind_of?(Array)
      path[0..-2].each do |child|
        return nil unless (options = options[child]) && options.respond_to?(:has_key?)
      end
      options[path[-1]]
    end

    # Merges the given default option at the given depth in the options hash
    # but only if the value is not set. Handles subhash merging by giving the
    # existing option key/value pairs precedence.
    #
    # === Parameters
    # path(Array|String):: path to option as an array of path elements or single
    #  string which may contain forward slashes as element name delimiters.
    # default_value(String):: default value to conditionally insert/merge or nil
    def default_option(path, default_value)
      # create subhashes to end of path.
      options = @options
      path = path.to_s.split('/') unless path.kind_of?(Array)
      path[0..-2].each { |child| options = options[child] ||= Mash.new }
      last_child = path[-1]

      # ensure any existing options override defaults.
      if default_value && options[last_child].respond_to?(:merge)
        options[last_child] = default_value.dup.merge(options[last_child])
      else
        options[last_child] ||= default_value
      end
    end

    # Creates the type using options specified by metadata kind, type category
    # and specific type, if given.
    #
    # === Parameters
    # kind(Token):: must be one of [:cloud_metadata, :user_metadata]
    # category(Token):: category for dependency class
    # type(String|Token):: specific type or nil
    #
    # === Return
    # dependency(Object):: new instance of dependency class
    def create_dependency_type(kind, category, dependency_type = nil)
      # support wildcard case for all dependency types in a category.
      kind = kind.to_sym
      category = category.to_sym
      if WILDCARD == dependency_type
        types = self.send(category)
        return types.map { |type| create_dependency_type(kind, category, type) }
      end

      # get specific type from category on cloud, if necessary.
      dependency_type = self.send(category) unless dependency_type
      raise NotImplementedError.new("The #{name.inspect} cloud has not declared a #{category} type.") unless dependency_type
      dependency_type = dependency_type.to_s

      options = resolve_options(kind, category, dependency_type)
      dependency_class = resolve_dependency(dependency_type)
      return dependency_class.new(options)
    end

    protected

    # Resolve options to pass to new object, giving precedency to most
    # specific options based on kind, category and type.
    #
    # === Parameters
    # kind(Token):: must be one of [:cloud_metadata, :user_metadata]
    # category(Token):: category for dependency class
    # type(String|Token):: specific type
    #
    # === Return
    # options(Hash):: resolved options
    def resolve_options(kind, category, type)
      # remove any module reference for type when finding options.
      type = type.to_s.gsub(/^.*\//, '').to_sym
      options = @options[category] ? @options[category].dup : Mash.new
      options = options.merge(@options[category][type]) if @options[category] && @options[category][type]
      if @options[kind] && @options[kind][category]
        options = options.merge(@options[kind][category])
        options = options.merge(@options[kind][category][type]) if @options[kind][category][type]
      end

      # set special options which should be available to all categories.
      options[:cloud] = self
      options[:logger] ||= @options[:logger]

      return options
    end

    # Creates the internal-use raw metadata writer.
    def raw_metadata_writer(kind)
      options = resolve_options(kind, :metadata_writers, RAW_METADATA_WRITER)
      return MetadataWriter.new(options)
    end

    # Called internally to execute a cloud extension script with the given
    # command-line arguments, if any. It is generally assumed scripts will not
    # exit until finished and will read any instance-specific information from
    # the system or from the output of write_metadata.
    #
    # === Parameters
    # script_path(String):: path to script to execute
    # arguments(Array):: arguments for script command line or empty
    #
    # === Return
    # result(ActionResult):: action result
    def execute_script(script_path, *arguments)
      cmd = ::RightScale::RightLinkConfig[:platform].shell.format_shell_command(script_path, *arguments)
      output = `#{cmd}`
      return ActionResult.new(:exitstatus => $?.exitstatus, :output => output)
    rescue Exception => e
      return ActionResult.new(:exitstatus => 1, :error => "ERROR: #{e.message}")
    end

    # make the given path relative to this cloud's DSL script path only if the
    # path is not already absolute.
    #
    # === Parameters
    # path(String):: absolute or relative path
    #
    # === Return
    # result(String):: absolute path
    def relative_to_script_path(path)
      path = path.gsub("\\", '/')
      unless path == File.expand_path(path)
        path = File.normalize_path(File.join(File.dirname(@script_path), path))
      end
      path
    end

  end  # Cloud

end  # RightScale
