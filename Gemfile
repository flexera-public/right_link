source 'http://gems.test.rightscale.com'
source 'https://rubygems.org'

gemspec

# Fresh off the assembly line
gem 'right_support', '~> 2.8'

gem 'right_agent', :git => 'git@github.com:rightscale/right_agent.git',
                   :branch => 'ivory_14_20_acu178887_rightscale_forks_update'

gem 'right_amqp', '~> 0.7'
gem 'right_popen', '~> 2.0'
gem 'right_git'
gem 'mime-types', '< 2.0'

gem 'right_scraper', '~> 4.0'

gem 'em-http-request', '1.0.3'
gem 'fiber_pool',      '1.0.0'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the 'custom' group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef', :git => 'git@github.com:rightscale/chef.git',
              :branch => 'ivory_14_18_acu178887_rightscale_11.14'
  gem 'ohai', '~> 7.2.4'
  gem 'mixlib-shellout', '~> 1.4.0', :git => 'git@github.com:rightscale/mixlib-shellout.git',
                                     :branch => 'ivory_14_21_acu180419_bump_version'
  gem 'eventmachine', '~> 1.0.0.4'
  gem 'rest-client', '1.7.0.3'
end

# we are now using mingw so the need to carefully lock Windows gems has been
# alleviated. chef has its own strict set of Windows gem dependencies but the
# following are specific to right_link.
group :windows do
  platform :mswin, :mingw do
    gem 'win32-dir'
    gem 'win32-process'
    gem 'win32-pipe'
  end
end

group :build do
  # This is work around for right_link package building with ruby 1.8 installed
  # while right_link gem is running on ruby 1.9
  gem 'rake', '~> 10.0'
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
gem 'ip'
