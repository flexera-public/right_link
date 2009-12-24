#!/opt/rightscale/sandbox/bin/ruby

# See lib/enroller.rb for additional information.

THIS_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
$:.push(File.join(File.dirname(THIS_FILE), 'lib'))

require 'rubygems'
require 'reenroller'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'nanite', 'lib', 'nanite'))

m = RightScale::Reenroller.new
opts = m.parse_args
m.run(opts)
