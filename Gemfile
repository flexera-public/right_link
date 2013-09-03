
source 'https://rubygems.org' 

gemspec

# Fresh off the assembly line
gem 'right_support', '~> 2.7'
gem 'right_agent', '~> 0.17'
gem 'right_amqp', '~> 0.7'
gem 'right_scraper', '~> 3.2'
gem 'right_popen', '~> 1.1'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the 'custom' group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef', '10.26.0.1'
  gem 'ohai', '6.16.0.1'
  gem 'mixlib-shellout', '1.1.0.1'
  gem 'eventmachine',    '1.0.0.3'
end

# We use some gems on both platforms, but the maintainer of the gem does not publish
# his own builds of the gem. We must do it for him. Therefore we cannot upgrade these
# gems without doing work on our side.
#
# DO NOT CHANGE VERSIONS of these gems until you have built a precompiled
# mswin-platform gem for every one of the gems below AND published it to
# the rightscale custom gem repository.
group :not_windows_friendly do
  gem 'json'
  gem 'nokogiri', '1.5.9'
  platform :mingw do
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
end

group :development do
  gem 'rake',               '0.8.7'
  gem 'rspec',              '~> 1.3'
  gem 'flexmock',           '~> 0.8'
  gem 'rubyforge',          '1.0.4'
  gem 'rcov', '~> 0.8.1',   :platforms => :mri_18
  gem 'ruby-debug',         :platforms => :mri_18
  gem 'ruby-debug19',       :platforms => :mri_19
  gem 'win32console',       :platforms => [:mswin, :mingw]
end

# Gems that are not dependencies of RightLink, but which are useful to
# include in the sandbox at runtime because they enhance compatibility
# with more OSes or provide debugging functionality.
group :runtime_extras do
  gem 'rb-readline',           '~> 0.5.0'
end

# Gems that are transitive dependencies of our direct deps, which we lock
# for paranoia's sake because we had them version locked in the pre-Gemfile
# days. Eventually we should stop version-locking these and let them 'float'
# as defined by our direct dependencies, and by Gemfile.lock.
# TODO - RightLink 6.0 - unlock these and let them float
group :stable do
  gem 'stomp',                 '1.1'
  gem 'ruby-openid',           '2.1.8'
  gem 'abstract',              '1.0.0'
  gem 'erubis',                '2.6.5'
  gem 'extlib',                '0.9.15'
  gem 'mixlib-cli',            '1.2.0'
  gem 'mixlib-config',         '1.1.2'
  gem 'mixlib-log',            '1.3.0'
  gem 'hoe',                   '2.3.3'
  gem 'moneta',                '0.6.0'
  gem 'bunny',                 '0.6.0'
  gem 'highline',              '1.6.9'
  gem 'uuidtools',             '2.1.2'
  gem 'mime-types',            '1.16'
  gem 'rest-client',           '1.6.7'
  gem 'msgpack',               '0.4.4'
  gem 'systemu',               '2.2.0'
end

gem 'mixlib-authentication', ">= 1.3.0"
