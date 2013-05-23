source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source 'https://rubygems.org' 

gemspec

# Fresh off the assembly line
gem 'right_support', '~> 2.7',
    :git => 'git://github.com/rightscale/right_support.git',
    :branch => 'master'
gem 'right_agent', '~> 0.15',
    :git => 'git://github.com/rightscale/right_agent.git',
    :branch => 'master'
gem 'right_amqp', '~> 0.6',
    :git => 'git://github.com/rightscale/right_amqp.git',
    :branch => 'master'
gem 'right_scraper', '~> 3.2',
    :git => 'git://github.com/rightscale/right_scraper.git',
    :branch => 'master'
gem 'right_popen', '~> 1.1'

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef',            '0.10.10.4'
  gem 'ohai',            '0.6.12.4'
  gem 'mixlib-shellout', '1.0.0.3'
  gem "eventmachine",    '1.0.0.3'
end

gem 'json'

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
  gem "ruby-debug19", :platforms => :mri_19
  gem "win32console", :platforms => [:mswin, :mingw]
end

# Gems that are transitive dependencies of our direct deps, which we lock
# for paranoia's sake because we had them version locked in the pre-Gemfile
# days. Eventually we should stop version-locking these and let them 'float'
# as defined by our direct dependencies, and by Gemfile.lock.
group :stable do
  gem "stomp",                 "1.1"
  gem "ruby-openid",           "2.1.8"
  gem "abstract",              "1.0.0"
  gem "erubis",                "2.6.5"
  gem "extlib",                "0.9.15"
  gem "mixlib-authentication", "1.1.2"
  gem "mixlib-cli",            "1.2.0"
  gem "mixlib-config",         "1.1.2"
  gem "mixlib-log",            "1.3.0"
  gem "hoe",                   "2.3.3"
  gem "moneta",                "0.6.0"
  gem "bunny",                 "0.6.0"
  gem "highline",              "1.6.9"
  gem "uuidtools",             "2.1.2"
  gem "mime-types",            "1.16"
  gem "rest-client",           "1.6.7"
  gem "msgpack",               "0.4.4"
end
