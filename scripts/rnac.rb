#!/opt/rightscale/sandbox/bin/ruby

# rnac --help for usage information
#
# See lib/agent_controller.rb for additional information.

THIS_DIR = File.dirname(File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__)
$:.push(File.join(THIS_DIR, 'lib'))

require 'agent_controller'

RightScale::AgentController.run
