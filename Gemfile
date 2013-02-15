source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source 'https://rubygems.org'

gemspec

# Fresh off the assembly line
gem 'right_support',   :git => 'git://github.com/rightscale/right_support.git',
                       :branch => 'teal_13_02_acu73023_mingw_193_discovery'
gem 'right_agent',     :git => 'git://github.com/rightscale/right_agent.git',
                       :branch => 'teal_13_02_acu73023_mingw_193_discovery'
gem 'right_amqp' ,     :git => 'git://github.com/rightscale/right_amqp.git',
                       :branch => 'teal_13_02_acu73023_mingw_193_discovery'
gem 'right_scraper',   :git => 'git://github.com/rightscale/right_scraper.git',
                       :branch => "teal_13_02_acu73023_mingw_193_discovery"
gem 'process_watcher', :git => 'git@github.com:rightscale/process_watcher.git',
                       :branch => "master"

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
  gem "win32-api",      "~> 1.4.5"
  gem "windows-api",    "~> 0.4.0"
  gem "windows-pr",     "~> 1.0"
  gem "win32-dir",      "~> 0.3.5"
  gem "win32-eventlog", "~> 0.5.2"
  gem "ruby-wmi",       "~> 0.4.0"
  gem "win32-process",  "~> 0.6.1"
  gem "win32-pipe",     "~> 0.2.1"
  gem "win32-service",  "~> 0.7.2"
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
