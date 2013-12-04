source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source 'https://rubygems.org'

gemspec

# Fresh off the assembly line
gem 'right_support', '~> 2.7'
gem 'right_agent', '~> 1.0.3'
gem 'right_amqp', '~> 0.7'
gem 'right_popen', '~> 2.0'

gem 'right_git', :git => 'git@github.com:rightscale/right_git.git',
                 :branch => 'teal_13_17_acu134044_support_mingw'

gem 'right_scraper', '~> 4.0',
                     :git => 'https://github.com/rightscale/right_scraper.git',
                     :branch => 'teal_13_17_acu134044_support_mingw'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the 'custom' group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef', '11.6.0.3'
  gem 'ohai', '6.18.0.2'
  gem 'mixlib-shellout', '1.2.0.2'
  gem 'eventmachine', '~> 1.0.0.4'
end

# We use some gems on both platforms, but the maintainer of the gem does not publish
# his own builds of the gem. We must do it for him. Therefore we cannot upgrade these
# gems without doing work on our side.
#
# DO NOT CHANGE VERSIONS of these gems until you have built a precompiled
# mswin-platform gem for every one of the gems below AND published it to
# the rightscale custom gem repository.
group :windows do
  platform :mswin, :mingw do
    # specific to right_link. chef has additional dependencies that should be
    # resolved by bundle installing on mingw.
    gem 'win32-dir'
    gem 'win32-process'
    gem 'win32-pipe'
  end
end

group :build do
  # This is work around for right_link package building with ruby 1.8 installed
  # while right_link gem is running on ruby 1.9
  gem 'rake', '0.8.7'
end

group :development do
  gem 'rspec', '~> 1.3'
  gem 'flexmock', '~> 0.9'
  gem 'rubyforge', '1.0.4'
  gem 'rcov', '~> 0.8.1',     :platforms => :mri_18
  gem 'ruby-debug',           :platforms => :mri_18
  gem 'debugger', '~> 1.6.1', :platforms => :mri_19
end

# Gems that are not dependencies of RightLink, but which are useful to
# include in the sandbox at runtime because they enhance compatibility
# with more OSes or provide debugging functionality.
group :runtime_extras do
  gem 'rb-readline', '~> 0.5.0'
end

gem 'mixlib-authentication', ">= 1.3.0"
