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

require 'rubygems'

# N.B. we can't use File#normalize_path yet because gems haven't been activated
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
  end
end

gem 'eventmachine'

gem 'right_support'
gem 'right_amqp'
gem 'right_agent'
gem 'right_popen'
gem 'right_http_connection'
gem 'right_scraper'

gem 'ohai'
gem 'chef'

if RightScale::Platform.windows?
  gem 'win32-api'
  gem 'windows-api'
  gem 'windows-pr'
  gem 'win32-dir'
  gem 'win32-eventlog'
  gem 'ruby-wmi'
  gem 'win32-process'
  gem 'win32-pipe'
  gem 'win32-open3'
  gem 'win32-service'
end
