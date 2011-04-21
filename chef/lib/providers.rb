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

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')

require 'chef'
require 'chef/client'

BASE_CHEF_LIB_DIR_PATH = File.normalize_path(File.dirname(__FILE__))
BASE_CHEF_PROVIDER_DIR_PATH = File.join(BASE_CHEF_LIB_DIR_PATH, 'providers')

# load (and self-register) all common providers
pattern = File.join(BASE_CHEF_PROVIDER_DIR_PATH, '*.rb')
Dir[pattern].each do |rb_file|
  require File.normalize_path(rb_file)
end

if RightScale::RightLinkConfig[:platform].windows?

  DYNAMIC_WINDOWS_CHEF_PROVIDERS_PATH = File.join(BASE_CHEF_LIB_DIR_PATH, 'windows')
  STATIC_WINDOWS_CHEF_PROVIDERS_PATH = File.join(BASE_CHEF_PROVIDER_DIR_PATH, 'windows')
  WINDOWS_CHEF_PROVIDERS_PATHS = [STATIC_WINDOWS_CHEF_PROVIDERS_PATH, DYNAMIC_WINDOWS_CHEF_PROVIDERS_PATH]

  # create the Windows default platform hash before loading windows providers.
  Chef::Platform.platforms[:windows] = { :default => { } } unless Chef::Platform.platforms[:windows]

  # load (and self-register) all static/dynamic Windows providers.
  WINDOWS_CHEF_PROVIDERS_PATHS.each do |base_path|
    pattern = File.join(base_path, '*.rb')
    Dir[pattern].each do |rb_file|
      require File.normalize_path(rb_file)
    end
  end

end
