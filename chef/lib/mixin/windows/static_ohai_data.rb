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

require 'ohai'

module RightScale

  # Represents any static Ohai initialization specific to Windows.
  class StaticOhaiData

    def create_initial_ohai
      # create and initialize Ohai in order to perform slow plugin
      # initialization at startup.
      @ohai = Ohai::System.new
      @ohai.all_plugins

      # disable any plugins which do not require refreshing following the
      # initial population of Ohai data.
      disable_static_ohai_windows_providers
    end

    def ohai
      # always return the same Ohai instance for refreshing.
      return @ohai
    end

    # Prevents running any ohai providers which represent static or rarely
    # updated information which is also time consuming to collect for every
    # converge. the effect is to make Ohai::System::refresh_plugins run more
    # efficiently.
    #
    # FIX: do we want to read this information from a configuration file?
    def disable_static_ohai_windows_providers
      disabled_plugins = Ohai::Config[:disabled_plugins]
      disabled_plugins << "kernel"
      disabled_plugins << "windows::kernel"
      disabled_plugins << "network"
      disabled_plugins << "windows::network"
      disabled_plugins << "platform"
      disabled_plugins << "windows::platform"
      disabled_plugins.uniq!
    end

  end

end
