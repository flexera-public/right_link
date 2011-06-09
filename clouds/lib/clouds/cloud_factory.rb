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

require 'singleton'

module RightScale

  # Singleton for registering and instantiating clouds.
  class CloudFactory

    include Singleton

    # exceptions
    class UnknownCloud < Exception; end

    # Registry method for a dynamic metadata type.
    #
    # === Parameters
    # cloud_names(Array|String):: name of one or more clouds (which may include DEFAULT_CLOUD) that use the given type
    # cloud_type(Class):: a cloud configuration type
    #
    # === Return
    # always true
    def register(cloud_aliases, cloud_type)
      # relies on each to split on newlines for strings and otherwise do each for collections.
      cloud_aliases.each { |cloud_alias| registered_type(cloud_alias, cloud_type) }
      true
    end

    # Factory method for dynamic metadata types.
    #
    # === Parameters
    # cloud(String):: a registered_type cloud name
    #
    # === Return
    # result(Object):: new instance of registered_type metadata type
    #
    # === Raise
    # UnknownCloud:: on error
    def create(cloud_name = nil, options = {})
      cloud_name = default_cloud_name unless cloud_name
      raise UnknownCloud.new("Unable to determine a default cloud") unless cloud_name
      cloud_type = registered_type(cloud_name)
      raise UnknownCloud.new("Unknown cloud: #{cloud_name}") unless cloud_type

      # just-in-time require cloud's list of dependencies in order to
      # avoid having to pre-require all cloud dependencies s when only one type
      # will actually be used.
      cloud_type.dependencies.each { |dependency| self.class.resolve_dependency(cloud_type, dependency) }
      cloud = cloud_type.new(options)
      cloud.name = cloud_name unless cloud.name
      cloud.abbreviation = cloud_abbreviation(cloud_type) unless cloud.abbreviation
      return cloud
    end

    # Determines the default cloud name. This currently relies on a 'cloud file'
    # which must be present in an expected RightScale location.
    #
    # === Return
    # result(String):: default cloud name or nil
    def default_cloud_name
      cloud_file_path = File.normalize_path(File.join(::RightScale::RightLinkConfig[:platform].filesystem.right_scale_state_dir, 'cloud'))
      return File.read(cloud_file_path).strip if File.file?(cloud_file_path)
      nil
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
    # cloud_type(Class):: cloud class
    # dependency(String|Token):: name for dependency class
    #
    # === Return
    # dependency(Class):: resolved dependency class
    def self.resolve_dependency(cloud_type, dependency)
      dependency_class_name = dependency.to_s.camelize
      begin
        dependency = Class.class_eval(dependency_class_name)
      rescue NameError
        dependency_base_paths = cloud_type.dependency_base_paths.dup << File.dirname(__FILE__)
        dependency_file_name = dependency + ".rb"
        dependency_base_paths.each do |dependency_base_path|
          file_path = File.normalize_path(File.join(dependency_base_path, dependency_file_name))
          if File.file?(file_path)
            require File.normalize_path(File.join(dependency_base_path, dependency))
            break
          end
        end
        dependency = Class.class_eval(dependency_class_name)
      end
      dependency
    end

    protected

    # Initialize configurators hash
    def initialize
      @cloud_types = {}
    end

    # Getter/setter for cloud types registry.
    def registered_type(cloud_alias, cloud_type = nil)
      raise ArgumentError.new("cloud_alias is required") unless cloud_alias
      cloud_alias = cloud_alias.to_s.strip.downcase
      cloud_type = @cloud_types[cloud_alias.to_sym] ||= cloud_type
      cloud_type.cloud_aliases(cloud_alias) if cloud_type
      cloud_type
    end

    # Determines the abbreviation for the given cloud type based on all
    # registered aliases.
    def cloud_abbreviation(cloud_type)
      aliases = cloud_type.cloud_aliases
      shortest = aliases.first.to_s
      aliases[1..-1].each { |a| shortest = a.to_s if a.to_s.length < shortest.length }
      return shortest.upcase
    end

  end
end
