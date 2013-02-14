source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source :rubygems

gemspec

# Fresh off the assembly line
gem 'right_support',           :git => 'git://github.com/rightscale/right_support.git',
    :branch => 'teal_13_02_acu73023_mingw_193_discovery'
gem 'right_agent',             :git => 'git://github.com/rightscale/right_agent.git',
    :branch => 'teal_13_02_acu73023_mingw_193_discovery'
gem 'right_amqp' ,             :git => 'git://github.com/rightscale/right_amqp.git',
    :branch => 'teal_13_02_acu73023_mingw_193_discovery'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef',            "0.10.10.3"
  gem 'ohai',            "0.6.12.1"
  gem 'mixlib-shellout', "1.0.0.1"
  gem "eventmachine",    "1.0.0"
end

gem "json"

platform :mingw do
  gem "win32-api"
  gem "windows-api"
  gem "windows-pr"
  gem "win32-dir"
  gem "win32-eventlog"
  gem "ruby-wmi"
  gem "win32-process"
  gem "win32-pipe"
  gem "win32-service"
end

group :development do
  gem "rake"
  gem "rspec",        "~> 1.3"
  gem "flexmock",     "~> 0.8"
  gem "rubyforge",    "1.0.4"
  gem "ruby-debug",   :platforms => :mri_18
  gem "ruby-debug19", :platforms => :mri_19
  gem "win32console", :platforms => [:mswin, :mingw]
end
