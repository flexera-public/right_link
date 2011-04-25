#
# Copyright (c) 2011 RightScale Inc
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

# This file may get required twice on Windows: Once using long path and once
# using short path. Since this is where we define the File.normalize_path
# method to alleviate this issue, we have a chicken & egg problem. So detect if
# we already required this file and skip the rest if that was the case
unless defined?(RUBY_PATCH_BASE_DIR)

# load platform-specific patches before any other patches (in order to define
# File.normalize_path, etc.)
if (RUBY_PLATFORM =~ /mswin/)
  require File.expand_path(File.join(File.dirname(__FILE__), 'ruby_patch', 'windows_patch'))
elsif (RUBY_PLATFORM =~ /linux/)
  require File.expand_path(File.join(File.dirname(__FILE__), 'ruby_patch', 'linux_patch'))
elsif (RUBY_PLATFORM =~ /darwin/)
  require File.expand_path(File.join(File.dirname(__FILE__), 'ruby_patch', 'darwin_patch'))
else
  raise LoadError, "Unsupported platform: #{RUBY_PLATFORM}"
end

RUBY_PATCH_BASE_DIR = File.normalize_path(File.join(File.dirname(__FILE__), 'ruby_patch'))

require File.join(RUBY_PATCH_BASE_DIR, 'string_patch')
require File.join(RUBY_PATCH_BASE_DIR, 'object_patch')

end # Unless already defined
