# === Synopsis:
#   RightScale run state reporter (rs_state) - (c) 2014 RightScale Inc
#
#   Report current run state of an instance
#
# === Examples:
#   Print the run state:
#   rs_state --type run
#   Possible values: booting, booting:reboot, operational, stranded,
#                    shutting-down:reboot, shutting-down:terminate, shutting-down:stop
#
#   Print the agent state:
#   rs_state --type agent
#   Possible values: pending, booting, operational, stranded, decommissioning, decommissioned
#
# === Usage
#    rs_state --type <type>
#
#    Options:
#      --type, -t TYPE  Display desired state(run or agent)
#      --verbose, -v    Display progress information
#      --help:          Display help
#      --version:       Display version information
#
#
require 'trollop'
require 'right_agent'
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'json_utilities'))

module RightScale

  class RightLinkStateController
    include CommandHelper

    def self.run
      m = RightLinkStateController.new
      m.control(m.parse_args)
    end

    def control(options)
      fail_if_right_agent_is_not_running
      check_privileges

      name = "get_instance_state_#{options[:type]}"
      result = JSON.parser.new(send_command({ :name => name }, options[:verbose]), JSON.load_default_options).parse
      fail(result['error']) if result['error']
      puts result['result']
    end

    def parse_args
      parser = Trollop::Parser.new do
        opt :type, "", :type => :string
        opt :verbose
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
      "rs_state #{right_link_version} - RightLink's run state reporter(c) 2014 RightScale"
    end
  end
end

#
# Copyright (c) 2009-2014 RightScale Inc
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
