# === Synopsis:
#   RightScale run state reporter (rs_state) - (c) 2013 RightScale Inc
#
#   Report current run state of an instance
#
# === Examples:
#   Print the run state:
#   rs_state --type=run
#   Possible values: booting, booting:reboot, operational, stranded,
#                    shutting-down:reboot, shutting-down:terminate, shutting-down:stop
#
#   Print the agent state:
#   rs_state --type=agent
#   Possible values: pending, booting, operational, stranded, decommissioning, decommissioned
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
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'json_utilities'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'instance_state'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'shutdown_request'))

module RightScale

  class RightLinkStateController
    include CommandHelper

    def self.run
      m = RightLinkStateController.new
      m.control(m.parse_args)
    end

    def silence_stdout
      save_stdout = STDOUT.dup
      STDOUT.reopen(RUBY_PLATFORM =~ /mswin|mingw/ ? 'NUL:' : '/dev/null')
      STDOUT.sync = true
      yield
    ensure
      STDOUT.reopen(save_stdout)
    end

    def control(options)
      silence_stdout { InstanceState.init(nil, true) } # RightScale::Log will log to STDOUT if no log file is provided
      result = case options[:type]
               when 'run'
                 case InstanceState.value
                 when 'booting'
                   "booting#{InstanceState.reboot? ? ':reboot' : ''}"
                 when 'operational'
                   "operational"
                 when 'stranded'
                   "stranded"
                 when 'decommissioning', 'decommissioned'
                   decom_reason = "unknown"
                   decom_reason = InstanceState.decommission_type if ShutdownRequest::LEVELS.include?(InstanceState.decommission_type)
                   "shutting-down:#{decom_reason}"
                 end
               when 'agent'
                 InstanceState.value
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
