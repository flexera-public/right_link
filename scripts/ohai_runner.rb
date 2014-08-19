# === Synopsis:
#   RightScale Ohai Runner - Copyright (c) 2014 by RightScale Inc
#
#   runs Ohai in the RightScale environment
#
# === Examples:
#
# === Usage:
#    rs_ohai [ohai node name]
#

require 'rubygems'
require 'right_agent'
require 'right_agent/scripts/usage'
require File.join(File.dirname(__FILE__), '..', 'lib', 'chef', 'ohai_setup')
require 'ohai/application'
if RightScale::Platform.windows?
  require 'ruby-wmi'
end
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))

module RightScale
  class OhaiRunner
    include CommandHelper
    # Activates RightScale environment before running ohai
    #
    # === Return
    # true:: Always return true
    def run
      $0 = "rs_ohai" # to prevent showing full path to executalbe in help banner
      Log.program_name = 'RightLink'
      init_logger
      RightScale::OhaiSetup.configure_ohai
      Ohai::Application.new.run
      true
    end
  end
end
