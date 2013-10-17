source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source 'https://rubygems.org'

gemspec

# Fresh off the assembly line
gem 'right_support', '~> 2.7'
gem 'right_agent', '~> 0.17'
gem 'right_amqp', '~> 0.7'

gem 'right_popen', '~> 2.0'
gem 'right_git'
gem 'right_scraper', '~> 4.0'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the 'custom' group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef', '11.6.0.2'
  gem 'ohai', '6.18.0.2'
  gem 'mixlib-shellout', '1.2.0.2'
  gem 'eventmachine', '1.0.0.3'
end

# We use some gems on both platforms, but the maintainer of the gem does not publish
# his own builds of the gem. We must do it for him. Therefore we cannot upgrade these
# gems without doing work on our side.
#
# DO NOT CHANGE VERSIONS of these gems until you have built a precompiled
# mswin-platform gem for every one of the gems below AND published it to
# the rightscale custom gem repository.
group :windows do
  gem 'json', '1.4.6'
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
  gem 'rcov', '~> 0.8.1',     :platforms => :mri_18
  gem 'ruby-debug',           :platforms => :mri_18
  gem 'debugger', '~> 1.6.1', :platforms => :mri_19
end

# Gems that are not dependencies of RightLink, but which are useful to
# include in the sandbox at runtime because they enhance compatibility
# with more OSes or provide debugging functionality.
group :runtime_extras do
  gem 'rb-readline',           '~> 0.5.0'
end

gem 'mixlib-authentication', ">= 1.3.0"
