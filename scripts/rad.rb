#!/opt/rightscale/sandbox/bin/ruby

# rad --help for usage information
#
# See lib/agent_deployer.rb for additional information.

THIS_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
$:.push(File.join(File.dirname(THIS_FILE), 'lib'))

require 'rubygems'
require 'agent_deployer'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'nanite', 'lib', 'nanite'))

RightScale::AgentDeployer.run

