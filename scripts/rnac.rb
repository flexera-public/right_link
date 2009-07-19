#!/usr/bin/env ruby

# rnac --help for usage information
#
# See lib/nanite_controller.rb for additional information.

THIS_DIR = File.dirname(File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__)
$:.push(File.join(THIS_DIR, 'lib'))

# Load AR before Nanite so that AR's JSON serializer gets
# overridden by the json gem's.
require 'active_record'
require 'nanite_controller'

RightScale::NaniteController.run
