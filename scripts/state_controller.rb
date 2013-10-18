# === Synopsis:
#   RightScale run state reporter (rs_state) - (c) 2013 RightScale Inc
#
#   Report current run state of an instance
#
# === Examples:
#   Print the run state:
#   rs_state --type=run
#
#   Print the agent state:
#   rs_state --type=agent
#
# === Usage
#    rs_state --type <type>
#
#    Options:
#      --type, -t TYPE  Display desired state(run or agent)
#      --help:          Display help
#      --version:       Display version information
#
#
require 'trollop'
require 'right_agent'
require File.expand_path(File.join(File.dirname(__FILE__), 'command_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'json_utilities'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'instance_state'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'shutdown_request'))

module RightScale

  class RightLinkStateController
    include CommandHelper

    def self.run
      m = RightLinkStateController.new
      m.control(m.parse_args)
    end

    def control(options)
      state = RightScale::JsonUtilities::read_json(InstanceState::STATE_FILE)
      result = case options[:type]
               when 'run'
                 case state['value']
                 when 'booting'
                   "booting#{state['reboot'] ? ':reboot' : ''}"
                 when 'operational'
                   "operational"
                 when 'decommissioning'
                   decom_reason = "unknown"
                   decom_reason = state['decommission_type'] if RightScale::ShutdownRequest::LEVELS.include?(state['decommission_type'])
                   "shutting-down:#{decom_reason}"
                 end
               when 'agent'
                 state['value']
               end
      fail("Failed to get #{options[:type]} state") unless result
      puts result
    rescue Exception => e
      fail(e)
    end

    def parse_args
      parser = Trollop::Parser.new do
        opt :type, "", :type => :string
        version ""
      end
      parse do
        options = parser.parse
        fail("No type specified on the command line.") unless options[:type]
        fail("Unknown state type '#{options[:type]}'. Use 'run' or 'agent'") unless ['run', 'agent'].include?(options[:type])
        options
      end
    end

    def usage
      Usage.scan(__FILE__)
    end

    def version
      "rs_state #{right_link_version} - RightLink's run state reporter(c) 2013 RightScale"
    end
  end
end
