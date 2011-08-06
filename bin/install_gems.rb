#!/opt/rightscale/sandbox/bin/ruby

# Copyright (c) 2009-2011 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

BASE_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))

require 'rubygems'
require 'fileutils'
require 'right_agent'
require File.join(BASE_DIR, 'lib', 'gem_utilities')

PKG_DIR              = ARGV[0] ? ARGV[0] : File.expand_path(File.join(BASE_DIR, 'pkg'))
COMMON_PKG_DIR_NAME  = 'common'
LINUX_PKG_DIR_NAME   = 'linux'
DARWIN_PKG_DIR_NAME  = 'darwin'
WINDOWS_PKG_DIR_NAME = 'windows'


# The canonical version of this logic lives in RightLink's config.rb but we cannot
# use it here due to chicken-and-egg problems with mixlib-config. In addition,
# this logic is vastly simpler in that it assumes a sandbox is present on the
# system and does not try to account for development environments.
#
# Please do not use this logic for your own purposes; instead, see config.rb.
# If you need to install gems in another context, see the GemUtilities module.
def gem_cmd
  platform = RightScale::Platform
  if platform.windows?
    # note that we cannot use the platform-specific filesystem calls because that
    # requires use of the win32-dir gem which is not (necessarily) present in the
    # initial sandbox.
    program_files_x86_env_var = ENV['ProgramFiles(x86)']
    program_files_path = program_files_x86_env_var ? program_files_x86_env_var : ENV['ProgramFiles']
    company_path = File.join(program_files_path, 'RightScale')
    ruby_bin_path = File.join(company_path, 'SandBox', 'Ruby', 'bin')

    # note that we cannot use the provided windows gem.bat because it pulls any
    # ruby.exe on the PATH instead of using the companion ruby.exe from the same
    # bin directory.
    %("#{ruby_bin_path}\\ruby.exe" "#{ruby_bin_path}\\gem")
  elsif platform.linux?
    '/opt/rightscale/sandbox/bin/gem'
  end
end

# If the package directory doesn't exist, do nothing
exit(0) unless File.exists?(PKG_DIR)

# we need to cd to the pkg dir specifically for the windows case because the
# windows gem can't handle space chars in the gem's parent directory names
# (e.g. "Program Files").
platform = RightScale::Platform
Dir.chdir(PKG_DIR) do
  common_dir = COMMON_PKG_DIR_NAME
  if platform.windows?
    platform_dir = WINDOWS_PKG_DIR_NAME
  elsif platform.darwin?
    platform_dir = DARWIN_PKG_DIR_NAME
  else
    platform_dir = LINUX_PKG_DIR_NAME
  end

  GemUtilities.install(common_dir, platform_dir, gem_cmd, STDOUT, true)
end
