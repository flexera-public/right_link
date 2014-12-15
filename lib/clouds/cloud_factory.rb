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
  # Subclass namespace
  module Clouds; end

  # Singleton for instantiating clouds.
  class CloudFactory

    include RightSupport::Ruby::EasySingleton

    # the unknown cloud is used to automatically detect current instance's cloud
    UNKNOWN_CLOUD_NAME = :unknown

    # exceptions
    class UnknownCloud < Exception; end

    # Registry method for a dynamic metadata type.
    #
    # === Parameters
    # cloud_name(String):: name of one or more clouds (which may include DEFAULT_CLOUD) that use the given type
    # cloud_script_path(String):: path to script used to describe cloud on creation
    #
    # === Return
    # always true
    def register(cloud_name, cloud_script_path)
      cloud_script_path = File.normalize_path(cloud_script_path)
      registered_type(cloud_name.to_s, cloud_script_path)
      true
    end

    # Resets the global cloud registry (to ensure a clean reload of cloud names).
    #
    # === Return
    # result(Hash):: Hash of cloud names to script paths before reset
    def reset_registry
      result = @names_to_script_paths
      @names_to_script_paths = nil
      result
    end

    # Gets the path to the script describing a cloud.
    #
    # === Parameters
    # cloud_name(String):: a registered_type cloud name
    #
    # === Return
    # cloud_script_path(String):: path to script used to describe cloud on creation
    #
    # === Raise
    # UnknownCloud:: on error
    def registered_script_path(cloud_name)
      cloud_script_path = registered_type(cloud_name)
      raise UnknownCloud.new("Unknown cloud: #{cloud_name}") unless cloud_script_path
      return cloud_script_path
    end

    # Factory method for dynamic metadata types.
    #
    # === Parameters
    # cloud(String):: a registered_type cloud name
    # options(Hash):: options for creation
    #
    # === Return
    # result(Object):: new instance of registered_type metadata type
    #
    # === Raise
    # UnknownCloud:: on error
    def create(cloud_name, options)
      raise ArgumentError.new("cloud_name is required") if cloud_name.to_s.empty?
      raise ArgumentError.new("options[:logger] is required") unless logger = options[:logger]
      raise UnknownCloud.new("No cloud definitions available.") unless @names_to_script_paths
      cloud_name = cloud_name.to_sym
      cloud_name = default_cloud_name if UNKNOWN_CLOUD_NAME == cloud_name
      raise UnknownCloud.new("Unable to determine a default cloud") if UNKNOWN_CLOUD_NAME == cloud_name
      cloud_script_path = registered_script_path(cloud_name)
      options = options.dup
      options[:name] ||= cloud_name.to_s
      options[:script_path] = cloud_script_path

      cloud = nil
      begin
        require cloud_script_path
        cloud_classname = cloud_name.to_s.capitalize
        cloud_class = eval("RightScale::Clouds::#{cloud_classname}")
        cloud = cloud_class.new(options)
      rescue LoadError => e
        raise ArgumentError, "Could not load Cloud class for #{cloud_name}, #{e}"
      end

      extend_cloud_by_scripts(cloud, logger)

      return cloud
    end

    # Getter for the default cloud name. This currently relies on a
    # 'cloud file' which must be present in an expected RightScale location.
    #
    # === Return
    # result(String):: content of the 'cloud file' or UNKNOWN_CLOUD_NAME
    def default_cloud_name
      cloud_file_path = RightScale::AgentConfig.cloud_file_path
      value = File.read(cloud_file_path).strip if File.file?(cloud_file_path)
      value.to_s.empty? ? UNKNOWN_CLOUD_NAME : value
    end

    # Normalizes a cloud name to ensure all variants are resolvable.
    #
    # === Parameters
    # cloud_name(String):: cloud name
    #
    # === Return
    # result(String):: normalized cloud name
    def self.normalize_cloud_name(cloud_name)
      return cloud_name.to_s.strip.downcase
    end

    protected

    # Getter/setter for cloud types registered clouds.
    #
    # === Parameters
    # name(String):: name of cloud
    # script_path(String):: path to script to evaluate when creating cloud
    #
    # === Return
    # result(Hash):: hash in form {:name => <name>, :script_path => <script_path>} or nil
    def registered_type(cloud_name, cloud_script_path = nil)
      raise ArgumentError.new("cloud_name is required") unless cloud_name
      key = self.class.normalize_cloud_name(cloud_name).to_sym
      @names_to_script_paths ||= {}
      @names_to_script_paths[key] ||= cloud_script_path
    end

    # Supports runtime extension of the cloud object by external scripts which
    # are associated with instance methods. These scripts can also override the
    # predefined methods (e.g. write_metadata) to further customize a cloud's
    # behavior on a given instance. It may also be better to run some complex
    # operation in a child process instead of in the process which is loading
    # the cloud object.
    #
    # === Parameters
    # @param [String] cloud as a registered_type or UNKNOWN_CLOUD_NAME
    # @param [Logger] logger
    def extend_cloud_by_scripts(cloud, logger)
      # search for script directories based first on any clouds which were
      # extended by the cloud and then by the exact cloud name.
      cloud_name = cloud.name.to_s
      base_klass = RightScale::Cloud
      # Note ancestors call returns current class as well. So the end result of 
      # this chain is a ordered list of classes from super-est to the current
      # class
      cloud_klasses = cloud.class.ancestors.select {|klass| klass.ancestors.include?(base_klass) && !(klass == base_klass)}

      search_paths = []
      cloud_klasses.reverse.each do |cloud_klass|
        cloud_alias = cloud_klass.cloud_name
        # first add default search path for cloud name.
        search_path = File.join(RightScale::Platform.filesystem.private_bin_dir, cloud_alias)
        if File.directory?(search_path)
          search_paths << search_path
          logger.debug("Added #{search_path.inspect} to search path for extension scripts.")
        else
          logger.debug("Optional extension script dir #{search_path.inspect} does not exist.")
        end

        # custom paths are last in order to supercede any preceeding extensions.
        cloud.extension_script_base_paths.each do |base_path|
          search_path = File.join(base_path, cloud_alias)
          if File.directory?(search_path)
            search_paths << search_path
            logger.debug("Added #{search_path.inspect} to search path for extension scripts.")
          else
            logger.debug("Optional extension script dir #{search_path.inspect} does not exist.")
          end
        end
      end

      # inject any scripts discovered in script paths as instance methods which
      # return the result of calling the external script.
      search_paths.each do |search_path|
        search_path = File.normalize_path(search_path)
        Dir.glob(File.join(search_path, "*")).each do |script_path|
          script_ext = File.extname(script_path)
          script_name = File.basename(script_path, script_ext)

          # ignore any script names which contain strange characters (like
          # semicolon) for security reasons.
          if script_name =~ /^[_A-Za-z][_A-Za-z0-9]*$/
            logger.debug("Extending #{cloud_name} from #{script_path.inspect}")
            eval_me = <<EOF
def #{script_name}(*arguments)
  return execute_script(\"#{script_path}\", *arguments)
end
EOF
            cloud.instance_eval(eval_me)
          end
        end
      end
    end

  end  # CloudFactory

end  # RightScale

# Register clouds
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'clouds'))
begin
  base_clouds_dir_path = File.join(File.dirname(__FILE__), 'clouds')

  # dynamically register all clouds using the script name as cloud name.
  pattern = File.join(base_clouds_dir_path, '*.rb')
  Dir[pattern].each do |cloud_script_path|
    cloud_name = File.basename(cloud_script_path, '.rb')
    RightScale::CloudFactory.instance.register(cloud_name, cloud_script_path)
  end
end

