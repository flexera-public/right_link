require 'chef'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper'))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'providers'))

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')
