#
# Copyright (c) 2010 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common', 'right_link_log'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'clouds', 'lib', 'clouds'))

module RightScale

  # provides details of configuring ohai for use in right_link environment.
  module OhaiSetup
    class SetupError < StandardError; end

    CUSTOM_PLUGINS_DIR_PATH = File.normalize_path(File.join(File.dirname(__FILE__), 'plugins'))

    def configure_ohai
      unless Ohai::Config[:plugin_path].include?(CUSTOM_PLUGINS_DIR_PATH)
        raise SetupError, "Missing custom Ohai plugins directory: \"#{CUSTOM_PLUGINS_DIR_PATH}\"" unless File.directory?(CUSTOM_PLUGINS_DIR_PATH)
        Ohai::Config[:plugin_path].unshift(CUSTOM_PLUGINS_DIR_PATH)
      end

      Ohai::Log.logger = RightLinkLog
      Ohai::Config.log_level(RightLinkLog.level_from_sym(RightLinkLog.level))
    end

    module_function :configure_ohai
  end

end
