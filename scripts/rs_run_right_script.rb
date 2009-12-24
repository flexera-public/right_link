#!/opt/rightscale/sandbox/bin/ruby

# run_recipe --help for usage information
#
# See lib/bundle_runner.rb for additional information.

THIS_FILE = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__
$:.push(File.join(File.dirname(THIS_FILE), 'lib'))

require 'rubygems'
require 'bundle_runner'
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'nanite', 'lib', 'nanite'))

r = RightScale::BundleRunner.new
opts = r.parse_args
opts[:bundle_type] = :right_script
r.run(opts)

