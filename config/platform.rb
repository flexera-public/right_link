#
# Copyright (c) 2009 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'darwin'))
require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'linux'))
require File.expand_path(File.join(File.dirname(__FILE__), 'platform', 'win32'))

module RightScale
  class PlatformError < StandardError; end
  
  class Platform		
		# Initialize platform values
		def initialize
			@windows = !!(RUBY_PLATFORM =~ /mswin/)
			@mac     = !!(RUBY_PLATFORM =~ /darwin/)
			@linux   = !!(RUBY_PLATFORM =~ /linux/)
		end

		# Is current platform windows?
		#
		# === Return
		# true:: If ruby interpreter is running on Windows
		# false:: Otherwise
		def windows?
			@windows
		end

		# Is current platform Mac OS X (aka Darwin)?
		#
		# === Return
		# true:: If ruby interpreter is running on Mac
		# false:: Otherwise
		def mac?
			@mac
		end

		# Is current platform linux?
		#
		# === Return
		# true:: If ruby interpreter is running on Linux
		# false:: Otherwise
		def linux?
			@linux
		end

    # Filesystem options object
    #
    # === Return
    # fs<Filesystem>:: Platform-specific filesystem config object
    def filesystem
      if linux?
        return Linux::Filesystem.new
      elsif mac?
        return Darwin::Filesystem.new
      elsif windows?
        return Win32::Filesystem.new
      else
        raise PlatformError.new("Don't know about the filesystem on this platform")
      end
    end

    # Linux platform-specific platform object
    #
    # === Return
    # instance of Platform::Linux:: If ruby interpreter is running on Linux
    # nil:: Otherwise
    def linux
      raise PlatformError.new("Only available under Linux") unless linux?
      return Linux.new
    end
	end
end

