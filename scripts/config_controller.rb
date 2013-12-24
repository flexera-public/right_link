# === Synopsis:
#   RightScale configuration manager (rs_config) - (c) 2013 RightScale Inc
#
#   Allows to get, set and list feature configuration values.
#
# === Examples:
#   Disable managed login:
#   rs_config --set managed_login off
#
#   Set decommission timeout:
#   rs_config --set decommission_timeout 180
#
#   Get decommission timeout:
#   rs_config --get decommission_timeout
#
# === Usage
#    rs_config (--list, -l | --set name value | --get name)
#
#    Options:
#     --list, -l                Lists all supported feature configurations and their values (if any).
#     --format, -f FMT          Output format for list operation(json, yaml, text)
#     --set, -s <name> <value>  Set feature name to specified value. name must be in supported feature list.
#                               Supported features: managed_login_enable, package_repositories_freeze,
#                                                   motd_update, decommission_timeout
#                               Valid values:       Positive integer for decommission_timeout
#                                                   on|off|true|false for rest of features
#     --get, -g <name>          Outputs the value of the given feature to stdout
#     --help                    Display help
#     --version                 Display version
#
#


require 'trollop'
require 'right_agent'
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'feature_config_manager'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'actors', 'instance_scheduler'))

module RightScale
  class RightLinkConfigController
    include CommandHelper
    SUPPORTED_FEATURES = %w[ managed_login_enable package_repositories_freeze motd_update decommission_timeout ]
    DEFAULTS = {
        "managed_login" => { "enable"=> true },
        "package_repositories" => { "freeze" => true},
        "motd" => { "update" => true},
        "decommission" => { "timeout" => InstanceScheduler::DEFAULT_SHUTDOWN_DELAY }
    }

    def self.run
      c = RightLinkConfigController.new
      c.control(c.parse_args)
    end

    def control(options)
      case options[:action]
      when :get
        puts FeatureConfigManager.get_value(options[:feature])
      when :set
        FeatureConfigManager.set_value(options[:feature], options[:value]);
      when :list
        puts format_output(DEFAULTS.merge(FeatureConfigManager.list), options[:format])
      end
    end

    def parse_args
      parser = Trollop::Parser.new do
        opt :list, ""
        opt :format, "", :type => :string, :default => "text"
        opt :set, "", :type => :string
        opt :get, "", :type => :string
        conflicts :format, :set
        conflicts :format, :get
        version ""
      end
      parse do
        options = parser.parse
        value = ARGV.shift if options[:set]
        action = :list if options.delete(:list)
        action, feature = :set, options.delete(:set) if options[:set]
        action, feature = :get, options.delete(:get) if options[:get]
        fail("No action specified") if action.nil?
        fail("Unsupported feature '#{feature}'") unless (action == :list || supported_feature?(feature))
        fail("Invalid value '#{value}' for #{feature}") unless (action != :set || valid_value?(feature, value))
        {
          :action   => action,
          :feature  => feature,
          :value    => prepare_value(value),
          :format   => parse_format(options[:format])
        }
      end
    end

    def prepare_value(value)
      case value
      when /^\d+$/          then value.to_i
      when /^(on|true)$/    then true
      when /^(off|false)$/  then false
      else value
      end
    end

    def supported_feature?(feature)
      SUPPORTED_FEATURES.include?(feature)
    end

    def valid_value?(feature, value)
      test_regex = feature == 'decommission_timeout' ? /^\d+$/ : /^(on|off|true|false)$/
      value =~ test_regex
    end

    def format_output(data, format)
      case format
      when :json
        JSON.pretty_generate(data)
      when :yaml
        YAML.dump(data)
      when :text
        data.map do |group_name, group|
          group.map { |feature, value| "#{group_name}_#{feature}=#{value}" }
        end.flatten.join("\n")
      else
        raise ArgumentError, "Unknown output format #{format}"
      end
    end

    def usage
      Usage.scan(__FILE__)
    end

    def version
      "rs_config #{right_link_version} - RightLink's configuration manager(c) 2013 RightScale"
    end

  end
end
