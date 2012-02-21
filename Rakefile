# Activate gem dependencies
require 'rubygems'
require 'bundler/setup'

# Ruby standard library dependencies
require 'fileutils'
require 'rake'
require 'rake/testtask'
require 'rdoc/task'
require 'rubygems/package_task'
# Extra components of gems that were activated above
require 'spec/rake/spectask'

# Project-specific dependencies
RIGHT_LINK_ROOT = File.dirname(__FILE__)

require File.join(RIGHT_LINK_ROOT, 'lib', 'run_shell')

include RunShell


def windows?
  return !!(RUBY_PLATFORM =~ /mswin/)
end

# Allows for debugging of order of spec files by reading a specific ordering of
# files from a text file, if present. all too frequently, success or failure
# depends on the order in which tests execute.
RAKE_SPEC_ORDER_FILE_PATH = ::File.join(RIGHT_LINK_ROOT, "rake_spec_order_list.txt")

# Setup path to spec files and spec options
#
# === Parameters
# t<Spec::Rake::SpecTask>:: Task instance to be configured
#
# === Return
# t<Spec::Rake::SpecTask>:: Configured task
def setup_spec(t)
  t.spec_opts = ['--options', "\"#{RIGHT_LINK_ROOT}/spec/spec.opts\""]
  t.spec_files = FileList["#{RIGHT_LINK_ROOT}/**/spec/**/*_spec.rb"].exclude(/^#{Regexp.quote(RIGHT_LINK_ROOT)}\/vendor/)

  # optionally read or write spec order for debugging purposes. use a stubbed
  # file with the text "FILL ME" to get the spec ordering for the current
  # machine.
  if ::File.file?(RAKE_SPEC_ORDER_FILE_PATH)
    if ::File.read(RAKE_SPEC_ORDER_FILE_PATH).chomp == "FILL ME"
      ::File.open(RAKE_SPEC_ORDER_FILE_PATH, "w") do |f|
        f.puts t.spec_files.to_a.join("\n")
      end
    else
      t.spec_files = FileList.new
      ::File.open(RAKE_SPEC_ORDER_FILE_PATH, "r") do |f|
        while (line = f.gets) do
          line = line.chomp
          (t.spec_files << line) if not line.empty?
        end
      end
    end
  end
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

if defined?(Spec)
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
      t.rcov_opts = lambda { IO.readlines("#{RIGHT_LINK_ROOT}/spec/rcov.opts").map {|l| l.chomp.split ' '}.flatten }
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

  desc "Run unit tests"
  if windows?
    task :units => [:clean, :build, :spec]
  else
    task :units => :spec
  end

  desc "Default to running unit tests"
  task :default => :units
end

namespace :git do
  desc "Install Git hooks located in lib/git_hooks"
  task :setup do
    git_hooks = File.join(File.dirname(__FILE__), ".git", "hooks")
    right_link_hooks = Dir[File.join(File.dirname(__FILE__), "lib", "git_hooks", "*.rb")]
    right_link_hooks.each do |hook|
      hook_name = hook.split("/").last.sub(".rb","")
      hook_path = File.join(git_hooks, hook_name)
      if windows?
        FileUtils.cp(hook, hook_path)
      else
        File.unlink hook_path if File.exists? hook_path
        File.symlink hook, hook_path
        File.chmod 0700, hook_path
      end
    end

  end
end

desc "Fire up IRB console with preloaded environment"
task :console => :load_env do
  ARGV[0] = nil
  IRB.start
end

task :load_env do
  require "rubygems"
  require "right_agent"
  require 'irb'
  BASE_DIR = File.join(File.dirname(__FILE__), 'lib')
  require File.normalize_path(File.join(BASE_DIR, 'instance'))
  require File.normalize_path(File.join(BASE_DIR, 'chef', 'providers'))
  require File.normalize_path(File.join(BASE_DIR, 'chef', 'plugins'))
  require File.normalize_path(File.join(BASE_DIR, 'repo_conf_generators'))
end

# Currently only need to build for Windows
if windows?
  def do_chef_node_cmdlet_task(task)
    ms_build_path = "#{ENV['WINDIR']}\\Microsoft.NET\\Framework\\v3.5\\msbuild.exe"
    Dir.chdir(File.join(RIGHT_LINK_ROOT, 'lib', 'chef', 'windows', 'ChefNodeCmdlet')) do
      # Note that we can build C# components using msbuild instead of needing to
      # have Developer Studio installed
      build_command = "#{ms_build_path} ChefNodeCmdlet.sln /t:#{task} /p:configuration=Release > ChefNodeCmdlet.build.txt 2>&1"
      puts "#{build_command}"
      `#{build_command}`
    end
  end

  desc "Cleans any binaries local to right_link"
  task :clean do
    do_chef_node_cmdlet_task(:clean)
  end

  desc "Builds any binaries local to right_link"
  task :build do
    do_chef_node_cmdlet_task(:build)
  end
end

#rake gemspec
spec = Gem::Specification.new do |s|
  s.name = 'right_link'
  s.version = '5.8.0'
  s.platform = Gem::Platform::RUBY
  s.description = "RightLink automates servers configuration and monitoring. It uses RabbitMQ as message bus and relies on Chef[2] for configuring. RightLink uses RightPopen[3] to monitor the stdout and stderr streams of scripted processes. Servers running the RightLink agent configures themselves on startup an register with the mapper so that operational recipes and scripts can be run at a later time."
  s.summary = "RightLink automates servers configuration and monitoring."
  exclude_folders = 'spec/rails/{doc,lib,log,nbproject,tmp,vendor,test}'
  exclude_files = FileList['**/*.log'] + FileList[exclude_folders+'/**/*'] + FileList[exclude_folders]
  s.files = FileList['{generators,lib,tasks,spec}/**/*'] + %w(init/init.rb LICENSE Rakefile README.rdoc) - exclude_files
  s.require_path = 'lib'
  s.has_rdoc = false
  s.test_files = Dir['spec/*_spec.rb']
  s.author = 'RightScale'
  s.email = 'support@rightscale.com'
  s.homepage = 'https://github.com/rightscale/right_link'
end

desc 'Generate a gemspec file.'
task :gemspec do
  File.open("#{spec.name}.gemspec", 'w') do |f|
    f.write spec.to_ruby
  end
end

Gem::PackageTask.new(spec) do |p|
  p.gem_spec = spec
  p.need_tar = RUBY_PLATFORM =~ /mswin/ ? false : true
  p.need_zip = true
end
