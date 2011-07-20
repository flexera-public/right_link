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

  module MetadataSources

    # Provides metadata by reading a dictionary file on disk.
    class SelectiveMetadataSource < MetadataSource

      attr_accessor :metadata_sources

      def initialize(options)
        raise ArgumentError, "options[:metadata_sources] is required" unless metadata_source_types = options[:metadata_source_types]
        raise ArgumentError, "options[:cloud] is required" unless @cloud = options[:cloud]
        @select_metadata_override = options[:select_metadata_override]

        # keep types but create selective sources on demand in case not all are used.
        @metadata_sources = []
        metadata_source_types.each do |metadata_source_type|
          @metadata_sources << { :type => metadata_source_type, :source => nil }
        end
      end

      # Queries for metadata using the given path.
      #
      # === Parameters
      # path(String):: metadata path
      #
      # === Return
      # metadata(String):: query result
      #
      # === Raises
      # QueryFailed:: on any failure to query
      def query(path)
        merged_metadata = ""
        last_query_failed = nil
        @metadata_sources.each do |metadata_source|
          type = metadata_source[:type]
          unless source = metadata_source[:source]
            # note that sources are special in that they ignore cloud vs. user
            # specialization unlike other dependency types.
            kind = :cloud_metadata
            source = @cloud.create_dependency_type(kind, :metadata_source, type)
            metadata_source[:source] = source
          end
          begin
            query_result = source.query(path)
            selected = select_metadata(path, type, query_result, merged_metadata)
            merged_metadata = selected[:merged_metadata]
            last_query_failed = nil  # reset last failed query
            break unless selected[:query_next_metadata]
          rescue QueryFailed => e
            # temporarily ignore failed query in case next source query succeeds
            last_query_failed = e
          end
        end
        raise last_query_failed if last_query_failed
        return merged_metadata
      rescue Exception => e
        raise QueryFailed.new(e.message)
      end

      # Selects metadata by determining if the metadata condition has been
      # satisfied. Supports merging of metadata (potentially in different
      # formats) from different sources.
      #
      # === Parameters
      # path(String):: metadata path
      # metadata_source_type(String):: metadata source type
      # query_result(String):: raw metadata from query
      # previous_metadata(String):: previously merged metadata or empty
      #
      # === Returns
      # result[:query_next_metadata](Boolean):: when true indicates that the next metadata source should also be queried.
      # result[:merged_metadata](String):: result of merging any previous metadata with current query result.
      def select_metadata(path, metadata_source_type, query_result, previous_metadata)
        return @select_metadata_override.call(self, path, metadata_source_type, query_result, previous_metadata) if @select_metadata_override
        return {:query_next_metadata => query_result.strip.empty?, :merged_metadata => query_result}
      end

      # Attempts to finish all child metadata sources.
      def finish
        last_exception = nil
        @metadata_sources.each do |metadata_source|
          begin
            source = metadata_source[:source]
            source.finish if source
          rescue Exception => e
            last_exception = e
          ensure
            metadata_source[:source] = nil
          end
        end
        raise last_exception if last_exception
      end

    end  # DictionaryFileMetadataSource

  end  # MetadataSources

end  # RightScale
