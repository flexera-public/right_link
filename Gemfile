source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source :rubygems

gem "rubyforge",               "1.0.4"
gem "rake",                    "0.8.7"
gem "encryptor",               "1.1.3"
gem "right_support",           "~> 1.4"
gem "right_amqp",              "~> 0.3",  :git => 'git@github.com:rightscale/right_amqp.git',    :branch => 'azure_12_6_ruby_19_mingw'
gem "right_agent",             "~> 0.10", :git => 'git@github.com:rightscale/right_agent.git',   :branch => 'azure_12_6_ruby_19_mingw'
gem "right_scraper",           "3.0.2",   :git => 'git@github.com:rightscale/right_scraper.git', :branch => 'azure_12_6_ruby_19_mingw'
gem "right_popen",             "~> 1.0"
gem "right_http_connection",   "~> 1.3"

# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem 'chef',            "0.10.10.2"
  gem 'ohai',            "0.6.12.1"
  gem 'mixlib-shellout', "1.0.0.1"
  gem "eventmachine",    "1.0.0"
end

# We use some gems on both platforms, but the maintainer of the gem does not publish
# his own builds of the gem. We must do it for him. Therefore we cannot upgrade these
# gems without doing work on our side.
#
# DO NOT CHANGE VERSIONS of these gems until you have built a precompiled
# mswin-platform gem for every one of the gems below AND published it to
# the rightscale custom gem repository.
group :not_windows_friendly do
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
end

group :test do
  gem "rspec",        "~> 1.3"
  gem "flexmock",     "~> 0.8"
  gem "ruby-debug",   :platforms => :mri_18
  gem "ruby-debug19", :platforms => :mri_19
  gem "win32console", :platforms => [:mswin, :mingw]
end

# Gems that are transitive dependencies of our direct deps, which we lock
# for paranoia's sake because we had them version locked in the pre-Gemfile
# days. Eventually we should stop version-locking these and let them 'float'
# as defined by our direct dependencies, and by Gemfile.lock.
group :stable do
  gem "stomp"
  gem "ruby-openid"
  gem "abstract"
  gem "erubis"
  gem "extlib"
  gem "mixlib-authentication"
  gem "mixlib-cli"
  gem "mixlib-config"
  gem "mixlib-log"
  gem "hoe"
  gem "moneta"
  gem "bunny"
  gem "process_watcher"
  gem "highline"
  gem "uuidtools"
  gem "mime-types"
  gem "rest-client"
end
