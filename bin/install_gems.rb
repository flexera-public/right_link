#!/opt/rightscale/sandbox/bin/ruby
#
# Copyright (c) 2009-2011 RightScale Inc
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

BASE_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))

require 'rubygems'
require 'rbconfig'
require 'fileutils'
require File.join(BASE_DIR, 'lib', 'gem_utilities')

PKG_DIR              = ARGV[0] ? ARGV[0] : File.expand_path(File.join(BASE_DIR, 'pkg'))
COMMON_PKG_DIR_NAME  = 'common'
LINUX_PKG_DIR_NAME   = 'linux'
DARWIN_PKG_DIR_NAME  = 'darwin'
WINDOWS_PKG_DIR_NAME = 'windows'

# Determine platform family
# Cannot use the RightScale::Platform capability here because it
# is inside the right_agent gem which cannot be assumed to be available yet
def platform
  case RbConfig::CONFIG['host_os']
  when /mswin|win32|dos|mingw|cygwin/i then :windows
  when /darwin/i then :darwin
  when /linux/i then :linux
  end
end

# The canonical version of this logic lives in RightLink's agent_config.rb.
# This logic is vastly simpler in that it assumes a sandbox is present on the
# system and does not try to account for development environments.
#
# Do not use this logic for your own purposes; instead, see agent_config.rb.
def gem_cmd
  if platform == :windows
    # Note that we cannot use the platform-specific filesystem calls because that
    # requires use of the win32-dir gem which is not (necessarily) present in the
    # initial sandbox
    program_files_x86_env_var = ENV['ProgramFiles(x86)']
    program_files_path = program_files_x86_env_var ? program_files_x86_env_var : ENV['ProgramFiles']
    company_path = File.join(program_files_path, 'RightScale')
    ruby_bin_path = File.join(company_path, 'SandBox', 'Ruby', 'bin')

    # Note that we cannot use the provided windows gem.bat because it pulls any
    # ruby.exe on the PATH instead of using the companion ruby.exe from the same
    # bin directory
    %("#{ruby_bin_path}\\ruby.exe" "#{ruby_bin_path}\\gem")
  else
    '/opt/rightscale/sandbox/bin/gem'
  end
end

# If the package directory doesn't exist, do nothing
exit(0) unless File.exists?(PKG_DIR)

# We need to cd to the pkg dir specifically for the windows case because the
# windows gem can't handle space chars in the gem's parent directory names
# (e.g. "Program Files")
Dir.chdir(PKG_DIR) do
  platform_dir = case platform
                 when :windows then WINDOWS_PKG_DIR_NAME
                 when :darwin  then DARWIN_PKG_DIR_NAME
                 when :linux   then LINUX_PKG_DIR_NAME
                 end
  GemUtilities.install([COMMON_PKG_DIR_NAME, platform_dir], gem_cmd, STDOUT, true)
end
