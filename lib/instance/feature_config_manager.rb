#
# Copyright (c) 2013 RightScale Inc
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
  class FeatureConfigManager
    class ReadWriteFeauteSet < RightSupport::Config::FeatureSet
      def set(feature_group, feature, value)
        configuration[feature_group] = {} unless configuration[feature_group]
        configuration[feature_group][feature] = value
      end

      def to_yaml
        configuration.to_yaml
      end
    end

    include RightSupport::Ruby::EasySingleton

    CONFIG_YAML_FILE = File.normalize_path(File.join(RightScale::Platform.filesystem.right_link_static_state_dir, 'features.yml'))

    def feature_enabled?(name)
      !!get_value(name)
    end

    def get_value(name)
      feature_group, feature = extract_group_and_feature(name)
      load_file
      @config[feature_group][feature]
    end

    def set_value(name, value)
      load_file
      feature_group, feature = extract_group_and_feature(name)
      @config.set(feature_group, feature, value)
      save_file
    end

    def list
      load_file
      @config
    end

private
    def load_file
      source = File.exists?(CONFIG_YAML_FILE) ? CONFIG_YAML_FILE : {}
      @config = ReadWriteFeauteSet.new(source)
    end

    def save_file
      File.open(CONFIG_YAML_FILE, "w") { |config| config.write(@config.to_yaml) }
    end

    # name of feature will be passed as package_repositories_freeze
    # but actual value for feature will be stored in @config['package_repositories']['freeze']
    def extract_group_and_feature(name)
      partition = name.rpartition("_")
      return partition.first, partition.last
    end
  end
end
