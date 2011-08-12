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
    class FileMetadataSource < MetadataSource

      # definitions for querying kinds of metadata by a simple path.
      DEFAULT_CLOUD_METADATA_ROOT_PATH = "cloud_metadata"
      DEFAULT_USER_METADATA_ROOT_PATH = "user_metadata"

      attr_accessor :cloud_metadata_source_file_path, :user_metadata_source_file_path

      def initialize(options)
        @cloud_metadata_source_file_path = options[:cloud_metadata_source_file_path]
        @cloud_metadata_root_path = options[:cloud_metadata_root_path] || DEFAULT_CLOUD_METADATA_ROOT_PATH

        @user_metadata_source_file_path = options[:user_metadata_source_file_path]
        @user_metadata_root_path = options[:user_metadata_root_path] || DEFAULT_USER_METADATA_ROOT_PATH
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
        result = ""
        if path == @cloud_metadata_root_path
          result = File.read(@cloud_metadata_source_file_path) if @cloud_metadata_source_file_path
        elsif path == @user_metadata_root_path
          result = File.read(@user_metadata_source_file_path) if @user_metadata_source_file_path
        else
          raise QueryFailed.new("Unknown path: #{path}")
        end
        result
      rescue Exception => e
        raise QueryFailed.new(e.message)
      end

      # Nothing to do.
      def finish
        true
      end

    end  # DictionaryFileMetadataSource

  end  # MetadataSources

end  # RightScale
