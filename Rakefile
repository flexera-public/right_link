# Activate gem dependencies
require 'rubygems'
require 'bundler/setup'
require 'rubygems/package_task'
require 'rake/clean'
require 'right_agent/minimal'

# Ruby standard library dependencies
require 'fileutils'

# Extra components of gems that were activated above
begin
  require 'spec/rake/spectask'
rescue ::LoadError => e
  warn "Test gems are not installed so test tasks will not work properly: #{e.message}"
end

# Project-specific dependencies
RIGHT_LINK_ROOT = File.dirname(__FILE__)

desc "Build right_link gem"
Gem::PackageTask.new(Gem::Specification.load("right_link.gemspec")) do |package|
  package.need_zip = true
  package.need_tar = true
end

CLEAN.include('pkg')

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
  if ::RightScale::Platform.windows?
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
      if ::RightScale::Platform.windows?
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
  require File.normalize_path(File.join(BASE_DIR, 'chef', 'right_providers'))
  require File.normalize_path(File.join(BASE_DIR, 'chef', 'plugins'))
  require File.normalize_path(File.join(BASE_DIR, 'repo_conf_generators'))
end

# Currently only need to build for Windows
if ::RightScale::Platform.windows?
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
