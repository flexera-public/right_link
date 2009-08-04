#!/usr/bin/env ruby

# rs_log_level --help for usage information
#
# See lib/log_level_manager.rb for additional information.

THIS_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
$:.push(File.join(File.dirname(THIS_FILE), 'lib'))

require 'rubygems'
require 'nanite'
require 'log_level_manager'

m = RightScale::LogLevelManager.new
opts = m.parse_args
m.run(opts)