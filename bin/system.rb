# Activate Bundler
require 'rubygems'
require 'bundler/setup'

# RubyGem dependencies
require 'json'
require 'right_agent'

# Standard library dependencies
require 'fileutils'
require 'socket'
require 'open-uri'

# RightLink Dependencies
$:.push(File.join(File.dirname(__FILE__), '..', 'scripts'))
require 'system_configurator'

Kernel.exit RightScale::SystemConfigurator.run
