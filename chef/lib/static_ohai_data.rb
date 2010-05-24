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

require 'singleton'

if RightScale::Platform.windows?
  require File.normalize_path(File.join(File.dirname(__FILE__), 'mixin', 'windows', 'static_ohai_data'))
else
  require File.normalize_path(File.join(File.dirname(__FILE__), 'mixin', 'linux', 'static_ohai_data'))
end

module RightScale

  # Represents any static Ohai initialization specific to the current platform.
  # The singleton has an instance method called "ohai" which is implemented in
  # a platform-specific manner.
  class StaticOhaiData
    include Singleton

    def initialize
      create_initial_ohai
    end

  end

  # pre-initialize the instance so that Ohai is perceived to refresh quickly
  # upon running first script.
  #
  # FIX: put initialization on a thread if we upgrade to Ruby 1.9.x
  StaticOhaiData.instance

end
