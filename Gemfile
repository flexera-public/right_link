source 'http://gems.test.rightscale.com'
source 'https://rubygems.org'

gemspec

# Proper open-source dependencies of the RightLink gem
gem 'right_support', '~> 2.8'

gem 'right_agent', '~> 2.6.0'

gem 'right_amqp', '~> 0.7'
gem 'right_popen', '~> 2.0'
gem 'right_git'
gem 'mime-types', '< 2.0'

gem 'right_scraper', '~> 4.0'

gem 'fiber_pool',      '1.0.0'
gem 'net-dhcp',        '~> 1.3'



# 0.5.1 break rightlink, interface changes. Don't upgrade till you go through
# and fix that up
# 0.4.0 and above is needed for proxy support
gem 'websocket-driver', '~>0.4.0'


gem 'mixlib-authentication', ">= 1.3.0"
gem 'ip'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the 'custom' group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  # Our version contains backported proxy support without bringing in new EM
  gem 'em-http-request', '1.0.3.1'
  gem 'eventmachine', '1.0.0.10'
  gem 'chef', '11.6.0.5'
  gem 'ohai', '6.18.0.2'
  gem 'mixlib-shellout', '1.2.0.2'
  gem 'rest-client', '1.7.0.4'
  # A requirement for our custom ohai fork, and metadata scraper. Needed
  # to get metadata for the Azure cloud for Windows/Linux
end

# we are now using mingw so the need to carefully lock Windows gems has been
# alleviated. chef has its own strict set of Windows gem dependencies but the
# following are specific to right_link.
group :windows do
  platform :mswin, :mingw do
    gem 'win32-dir'
    gem 'win32-process'
    # Keep version at 0.3.3, version 0.3.5 breaks specs
    gem 'win32-pipe', "0.3.3"
  end
end

group :build do
  # This is work around for right_link_package building with ruby 1.8 installed
  # while right_link gem is running on ruby 1.9
  gem 'rake', '~> 10.0'
end

# Gems that are needed to run tests
group :test do
  gem 'right_develop', '~> 3.1'
  gem 'rspec', '~> 1.3'
  # TODO: upgrade to RSpec 2.x and flexmock 1.x, avoid spurious Test::Unit output
  gem 'flexmock', '~> 0.9'
end

# Gems that are useful for development, but not available in CI.
group :development do
  gem 'rubyforge', '1.0.4'
  gem 'ruby-debug',           :platforms => :mri_18
  gem 'debugger', '~> 1.6.1', :platforms => :mri_19
end

# Gems that are not dependencies of RightLink, but which are useful to
# include in the sandbox at runtime because they enhance compatibility
# with more OSes or provide debugging functionality.
group :runtime_extras do
  gem 'rb-readline', '~> 0.5.0'
end
