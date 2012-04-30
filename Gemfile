source 'http://s3.amazonaws.com/rightscale_rightlink_gems_dev'
source :rubygems

gem "rubyforge",               "1.0.4"
gem "rake",                    "0.8.7"
gem "right_support",           "~> 1.4"
gem "right_amqp",              "~> 0.2.0"
gem "right_agent",             :git     => 'git://github.com/rgeyer/right_agent',
                               :branch  => 'windows_assign_path'
gem "right_popen",             "~> 1.0"
gem "right_http_connection",   "~> 1.3.0"
gem "right_scraper",           "3.0.1"
# We have custom builds of some gems containing fixes and patches that are specific
# to RightScale. Gems in the "custom" group are published by RightScale to our
# custom gem repository (http://s3.amazonaws.com/rightscale_rightlink_gems_dev).
group :custom do
  gem "ohai",                  "0.6.11.3"
  gem "chef",                  "0.10.8.5"
  gem "eventmachine",          "0.12.11.6"
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

group :test do
  gem "ruby-debug"
  gem "rspec",                 "~> 1.3"
  gem "flexmock",              "~> 0.8"
  platform :mswin do
    gem "win32console",        "~> 1.3.0"
  end
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
  gem "extlib",                "0.9.14"
  gem "mixlib-authentication", "1.1.2"
  gem "mixlib-cli",            "1.2.0"
  gem "mixlib-config",         "1.1.2"
  gem "mixlib-log",            "1.3.0"
  gem "hoe",                   "2.3.3"
  gem "moneta",                "0.6.0"
  gem "bunny",                 "0.6.0"
  gem "process_watcher",       "0.4"
  gem "highline",              "1.6.1"
  gem "uuidtools",             "2.1.2"
  gem "mime-types",            "1.16"
  gem "rest-client",           "1.6.7"
end
