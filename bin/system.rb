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

# Cloud meta-data
require '/var/spool/cloud/meta-data-cache' if  File.exists?('/var/spool/cloud/meta-data-cache')
require '/var/spool/cloud/user-data.rb' if File.exists?('/var/spool/cloud/user-data.rb')

Kernel.exit RightScale::SystemConfigurator.run
