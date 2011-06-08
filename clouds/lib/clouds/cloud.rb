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

module RightScale

  # Mixin for a cloud type. Multiple clouds can reuse the same cloud type if the
  # behavior is similar.
  module Cloud

    def self.included(base)
      base.extend ClassMethods
      base.send(:include, InstanceMethods)
    end

    module ClassMethods

      # Aliases for cloud (or other clouds which have the same behavior).
      def cloud_aliases(cloud_alias = nil)
        @cloud_aliases ||= []
        @cloud_aliases << cloud_alias if cloud_alias && !@cloud_aliases.include?(cloud_alias)
        @cloud_aliases
      end

      # Runtime cloud depedencies (loaded on demand).
      def dependencies(*args)
        @dependencies ||= []
        args.each { |dependency| @dependencies << dependency unless @dependencies.include?(dependency) }
        @dependencies
      end

      # Base paths for runtime cloud depedencies in order of priority. Defaults
      # to location of cloud module files.
      def dependency_base_paths(*args)
        @dependency_base_paths ||= []
        args.each { |dependency_base_path| @dependency_base_paths << dependency_base_path unless @dependency_base_paths.include?(dependency_base_path) }
        @dependency_base_paths
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

    end  # ClassMethods

    module InstanceMethods

      CLOUD_METADATA_FILE_PREFIX = 'meta-data'
      USER_METADATA_FILE_PREFIX = 'user-data'
      WILDCARD = '*'

      attr_accessor :name, :abbreviation

      # Initializer.
      #
      # === Parameters
      # options(Hash):: options grab bag used to configure cloud and dependencies.
      def initialize(options)
        @options = JSON::parse(options.to_json)  # break options lineage
        default_options(@options, [:metadata_writers, :output_dir_path], File.join(RightScale::Platform.filesystem.spool_dir, 'cloud'))
        default_options(@options, [:cloud_metadata, :metadata_formatter, :formatted_path_prefix], "#{@abbreviation.upcase}_")
        default_options(@options, [:cloud_metadata, :metadata_writers, :file_name_prefix], CLOUD_METADATA_FILE_PREFIX)
        default_options(@options, [:user_metadata, :metadata_writers, :file_name_prefix], USER_METADATA_FILE_PREFIX)
      end

      # Reads the generated metadata file of the given kind and writer type.
      #
      # === Parameters
      # kind(Symbol):: kind of metadata must be one of [:cloud_metadata, :user_metadata]
      # writer_type(Symbol):: writer_type [:raw, ...]
      def read_metadata(kind, writer_type = :raw, subpath = nil)
        if :raw == writer_type
          reader = raw_metadata_writer(kind)
        else
          reader = create_dependent_type(kind, :metadata_writers, writer_type)
        end
        return reader.read(subpath)
      end

      # Queries and writes current metadata to file.
      #
      # === Parameters
      # kind(Symbol):: kind of metadata must be one of [:cloud_metadata, :user_metadata, WILDCARD]
      #
      # === Return
      # always true
      def write_metadata(kind = WILDCARD)
        writers = create_dependent_type(kind, :metadata_writers, WILDCARD)
        formatter = create_dependent_type(kind, :metadata_formatter)
        kinds = [:cloud_metadata, :user_metadata].select { |k| WILDCARD == kind || k == kind }
        kinds.each do |k|
          metadata = query_metadata(k)
          metadata = formatter.format_metadata(metadata)
          writers.each { |writer| writer.write(metadata) }
        end
        true
      ensure
        # release metadata source after querying all metadata.
        temp_metadata_source = @metadata_source
        @metadata_source = nil
        temp_metadata_source.finish
      end

      # Convenience method for reading only cloud metdata.
      def read_cloud_metadata(writer_type = :raw, subpath = nil); read_metadata(:cloud_metadata, writer_type, subpath); end

      # Convenience method for reading only cloud metdata.
      def read_cloud_metadata(writer_type = :raw, subpath = nil); read_metadata(:user_metadata, writer_type, subpath); end

      # Convenience method for writing only cloud metdata.
      def write_cloud_metadata; write_metadata(:cloud_metadata); end

      # Convenience method for writing only user metdata.
      def write_user_metadata; write_metadata(:user_metadata); end

      protected

      # Executes a query for metadata and builds a metadata 'tree' according to
      # the rules of provider and tree climber.
      #
      # === Parameters
      # kind(Token):: must be one of [:cloud_metadata, :user_metadata]
      #
      # === Return
      # metadata(Hash):: Hash-like metadata response
      def query_metadata(kind)
        @metadata_source = create_dependent_type(kind, :metadata_source) unless @metadata_source
        metadata_tree_climber = create_dependent_type(kind, :metadata_tree_climber)
        provider = create_dependent_type(kind, :metadata_provider)
        provider.send(:metadata_source, @metadata_source)
        provider.send(:metadata_tree_climber, metadata_tree_climber)
        provider.send(:raw_metadata_writer, raw_metadata_writer(kind))

        # query
        metadata = @provider.send(:build_metadata)

        # format
        formatter = create_dependent_type(kind, :metadata_formatter)
        metadata = formatter.format_metadata(metadata)
        metadata
      ensure
        # release metadata source if it is not reusable.
        if @metadata_source && !@metadata_source.reusable
          temp_metadata_source = @metadata_source
          @metadata_source = nil
          temp_metadata_source.finish
        end
      end

      # Merges the given default options at the given depth in the options hash.
      #
      # === Parameters
      # options(Hash):: caller options
      # path(Array|String):: path to option as an array of path elements or single string
      # defaults(Object):: object of any kind representing option to merge
      def default_options(options, path, defaults)
        # create subhashes to end of path.
        path[0..-2].each { |child| options = options[child] ||= {} }
        last_child = path[-1]
        if options[last_child].respond_to?(:merge)
          # ensure any existing options override defaults.
          options[last_child] = defaults.dup.merge(options[last_child])
        else
          options[last_child] = defaults
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
      def create_dependent_type(kind, category, type = nil)
        # support wildcard case for all dependency types in a category.
        kind = kind.to_sym
        category = category.to_sym
        if WILDCARD == type
          types = self.send(category)
          return types.map { |t| create_dependent_type(kind, category, t) }
        end

        # get specific type from category on cloud, if necessary.
        type = self.send(category) unless type
        raise NotImplementedError.new("The #{name.inspect} cloud has not declared a #{category} type.") unless type
        type = type.to_s

        options = resolve_options(kind, category, type)
        dependency = CloudFactory.instance.resolve_dependency(self.class, type)
        return dependency.new(options)
      end

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
        options = @options[category] ? @options[category].dup : {}
        options = options.merge(@options[category][type]) if @options[category] && @options[category][type]
        if @options[kind] && @options[kind][category]
          options = options.merge(@options[kind][category])
          options = options.merge(@options[kind][category][type])
        end
        options
      end

      # Creates the internal-use raw metadata writer.
      def raw_metadata_writer(kind)
        options = resolve_options(kind, :metadata_writers, :raw)
        return MetadataWriter.new(options)
      end

    end  # InstanceMethods

  end  # Cloud

end  # RightScale
