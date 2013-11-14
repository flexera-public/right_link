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

# RVM pollutes the process environment with garbage that prevents us from activating sandboxed
# RubyGems correctly. Unpollute the environment so our built-in RubyGems can setup the variables
# appropriately for our own usage (and for installation of gems into the sandbox!)
['GEM_HOME', 'GEM_PATH', 'IRBRC', 'MY_RUBY_HOME'].each { |key| ENV.delete(key) }

require 'rubygems'

# Note: can't use File#normalize_path (for Windows safety) yet because it's
# defined by right_agent and gems haven't been activated yet.
basedir = File.expand_path(File.join(File.dirname(__FILE__), '..'))

Dir.chdir(basedir) do
  if File.exist?('Gemfile')
    # Development mode: activate Bundler gem, then let it setup our RubyGems
    # environment for us -- but don't have it auto-require any gem files; we
    # will do that ourselves.
    require 'bundler'
    Bundler.setup
  else
    # Release mode: use 'bare' RubyGems; assume that all gems were installed
    # as system gems. Nothing to do here...
    gem 'right_link'

    gem 'eventmachine'

    gem 'right_support'
    gem 'right_amqp'
    gem 'right_agent'
    gem 'right_popen'
    gem 'right_http_connection'
    gem 'right_scraper'

    gem 'ohai'
    gem 'chef'

    # Note: can't use RightScale::Platform because gem sources aren't loaded
    if RUBY_PLATFORM =~ /mswin|mingw/
      gem 'win32-api'
      gem 'windows-api'
      gem 'windows-pr'
      gem 'win32-dir'
      gem 'rdp-ruby-wmi'
      gem 'win32-process'
      gem 'win32-pipe'
      gem 'win32-service'
    end
  end
end

# Make sure gem bin directories appear at the end of the PATH so our wrapper
# scripts (e.g. those installed to /usr/bin) get top billing *iff* a bin dir
# already appears on the PATH. Notice we choose regexp patterns that work under
# both Linux and Windows.
sep = (RUBY_PLATFORM =~ /mswin|mingw/) ? ';' : ':'
version = RUBY_VERSION.split('.')[0..1].join('.')
subdir = /(ruby|gems)[\\\/]#{version}[\\\/]bin/
paths = ENV['PATH'].split(sep)
gem_bin = paths.select { |p| p =~ subdir }
paths.delete_if { |p| p =~ subdir }
ENV['PATH'] = (paths + gem_bin).join(sep)
