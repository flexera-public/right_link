require 'spec/rake/spectask'
require 'fileutils'

# Usage (rake --tasks):
#
# rake autotest           # Run autotest
# rake autotest:rcov      # Run RCov when autotest successful
# rake spec               # Run all specs in all specs directories
# rake spec:clobber_rcov  # Remove rcov products for rcov
# rake spec:doc           # Print Specdoc for all specs
# rake spec:rcov          # Run all specs all specs directories with RCov

RIGHT_BOT_ROOT = File.dirname(__FILE__)

# Setup path to spec files and spec options
#
# === Parameters
# t<Spec::Rake::SpecTask>:: Task instance to be configured
#
# === Return
# t<Spec::Rake::SpecTask>:: Configured task
def setup_spec(t)
  t.spec_opts = ['--options', "\"#{RIGHT_BOT_ROOT}/spec/spec.opts\""]
  t.spec_files = FileList["#{RIGHT_BOT_ROOT}/**/spec/**/*_spec.rb"]
  t
end

# Setup environment variables for autotest and check installation
#
# === Return
# true:: Autotest setup is OK
# false:: Otherwise
def setup_auto_test
  ENV['RSPEC']    = 'true'     # allows autotest to discover rspec
  ENV['AUTOTEST'] = 'true'  # allows autotest to run w/ color on linux
#  $:.push(File.join(File.dirname(__FILE__), 'spec'))
  system((RUBY_PLATFORM =~ /mswin|mingw/ ? 'autotest.bat' : 'autotest'), *ARGV) ||
  $stderr.puts('Unable to find autotest. Please install ZenTest or fix your PATH') && false
end

# Default to running unit tests
task :default => :spec

# List of tasks
desc 'Run all specs in all specs directories'
Spec::Rake::SpecTask.new(:spec) do |t|
  setup_spec(t)
end

namespace :spec do
  desc 'Run all specs all specs directories with RCov'
  Spec::Rake::SpecTask.new(:rcov) do |t|
    setup_spec(t)
    t.rcov = true
    t.rcov_opts = lambda { IO.readlines("#{RIGHT_BOT_ROOT}/spec/rcov.opts").map {|l| l.chomp.split ' '}.flatten }
  end

  desc 'Print Specdoc for all specs (excluding plugin specs)'
  Spec::Rake::SpecTask.new(:doc) do |t|
    setup_spec(t)
    t.spec_opts = ['--format', 'specdoc', '--dry-run']
  end
end

desc 'Run autotest'
task :autotest do
  setup_auto_test
end

namespace :autotest do
  desc 'Run RCov when autotest successful'
  task :rcov do
    ENV['RCOV'] = 'true'
    setup_auto_test
  end
end
