#!/opt/rightscale/sandbox/bin/ruby

# rs_log_level --help for usage information
#
# See lib/log_level_manager.rb for additional information.

THIS_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
$:.push(File.join(File.dirname(THIS_FILE), 'lib'))

require 'rubygems'
require 'log_level_manager'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'nanite', 'lib', 'nanite'))

m = RightScale::LogLevelManager.new
opts = m.parse_args
m.run(opts)
