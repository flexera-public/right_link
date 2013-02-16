source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source :rubygems

gemspec

# Fresh off the assembly line
gem "iconv"
gem 'right_support',           :git => 'git://github.com/rightscale/right_support.git',
    :branch => 'master'
gem 'right_agent',             :git => 'git://github.com/kbockmanrs/right_agent.git',
    :branch => 'freebsd2'
gem 'right_amqp' ,             :git => 'git://github.com/rightscale/right_amqp.git',
    :branch => 'master'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef',            "0.10.10.3"
  gem 'ohai',            "0.6.12.1"
  gem 'mixlib-shellout', "1.0.0.1"
  gem "eventmachine",    "1.0.0.2"
end

# We use some gems on both platforms, but the maintainer of the gem does not publish
# his own builds of the gem. We must do it for him. Therefore we cannot upgrade these
# gems without doing work on our side.
#
# DO NOT CHANGE VERSIONS of these gems until you have built a precompiled
# mswin-platform gem for every one of the gems below AND published it to
# the rightscale custom gem repository.
group :not_windows_friendly do
  gem "json",                  "1.4.6"
end

# These dependencies are included in the gemspec via a dirty hack. We declare them
# here out of a sense of guilt, and in order to ensure that Bundler plays well with
# others on both platforms.
# @see http://stackoverflow.com/questions/4596606/rubygems-how-do-i-add-platform-specific-dependency
group :windows do
  platform :mswin do
    gem "win32-api",           "1.4.5"
    gem "windows-api",         "0.4.0"
    gem "windows-pr",          "1.0.8"
    gem "win32-dir",           "0.3.5"
    gem "win32-eventlog",      "0.5.2"
    gem "ruby-wmi",            "0.2.2"
    gem "win32-process",       "0.6.1"
    gem "win32-pipe",          "0.2.1"
    gem "win32-open3",         "0.3.2"
    gem "win32-service",       "0.7.2"
  end
end

group :development do
  gem "rake"
  gem "ruby-debug"
  gem "rspec",                 "~> 1.3"
  gem "flexmock",              "~> 0.8"
  gem "rubyforge",               "1.0.4"
  platform :mswin do
    gem "win32console",        "~> 1.3.0"
  end
end
