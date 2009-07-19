# === Synopsis:
#   RightScale Agent Deployer (rad) - (c) 2009 RightScale
#
#   rad is a command line tool that allows building the configuration file for
#   a given agent.
#   The configuration files will be generated in:
#     right_net/generated/<name of agent>/config.yml
#
# === Examples:
#   Build configuration for AGENT with default options:
#     rad AGENT
#
#   Build configuration for AGENT so it uses given AMQP settings:
#     rad AGENT --user USER --pass PASSWORD --vhost VHOST --port PORT --host HOST
#     rad AGENT -u USER -p PASSWORD -v VHOST -P PORT -h HOST
#
#  === Usage:
#    rad AGENT [options]
#
#    options:
#      --identity, -i ID      Use base id ID to build agent's identity
#      --token, -t TOKEN      Use token TOKEN to build agent's identity
#      --prefix, -r PREFIX:   Prefix nanite agent identity with PREFIX
#      --user, -u USER:       Set agent AMQP username
#      --password, -p PASS:   Set agent AMQP password
#      --vhost, -v VHOST:     Set agent AMQP virtual host
#      --port, -P PORT:       Set AMQP server port
#      --host, -h HOST:       Set AMQP server host
#      --actors-dir, -a DIR:  Set directory containing actor classes
#      --pid-dir, -z DIR:     Set directory containing pid file
#      --monit, -w:           Generate monit configuration file
#      --options, -o KEY=VAL: Pass-through options
#      --test:                Build test deployment using default test settings
#      --help:                Display help
#      --version:             Display version information

require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'yaml'
require 'ftools'
require 'fileutils'
require 'nanite'
require File.join(File.dirname(__FILE__), 'rdoc_patch')
require File.join(File.dirname(__FILE__), 'agent_utils')
require File.join(File.dirname(__FILE__), 'common_parser')

module RightScale

  class AgentDeployer

    include Utils
    include CommonParser

    VERSION = [0, 2]

    # Helper
    def self.run
      d = AgentDeployer.new
      d.generate_config(d.parse_args)
    end

    # Do deployment with given options
    def generate_config(options)
      init_rb_path = nil
      actors = nil
      actors_path = nil
      actors_path = options[:actors_dir] || actors_dir
      cfg = agent_config(options[:agent])
      fail("Cannot read configuration for agent #{options[:agent]}") unless cfg
      actors = cfg.delete(:actors)
      fail('Agent configuration does not define actors') unless actors && actors.respond_to?(:each)
      actors.each do |actor|
        actor_file = File.join(actors_path, "#{actor}.rb")
        fail("Cannot find actor file '#{actor_file}'") unless File.exist?(actor_file)
      end
      options[:actors_path] = actors_path
      options[:actors] = actors
      options[:init_rb_path] = File.join(agent_dir(options[:agent]), options[:agent] + ".rb")
      options[:pid_prefix] = 'nanite'
      write_config(options)
    end

    # Generate configuration files
    def write_config(options)
      cfg = {}
      cfg[:identity]   = options[:identity] if options[:identity]
      cfg[:pid_dir]    = options[:pid_dir] || '/var/run'
      cfg[:user]       = options[:user] if options[:user]
      cfg[:pass]       = options[:pass] if options[:pass]
      cfg[:vhost]      = options[:vhost] if options[:vhost]
      cfg[:port]       = options[:port] if options[:port]
      cfg[:host]       = options[:host] if options[:host]
      cfg[:initrb]     = options[:init_rb_path] if options[:init_rb_path]
      cfg[:actors]     = options[:actors] if options[:actors]
      cfg[:actors_dir] = options[:actors_path] if options[:actors_path]
      cfg[:format]     = 'secure'
      options[:options].each { |k, v| cfg[k] = v } if options[:options]

      agent_dir = gen_agent_dir(options[:agent])
      File.makedirs(agent_dir) unless File.exist?(agent_dir)
      conf_file = config_file(options[:agent])
      File.delete(conf_file) if File.exist?(conf_file)
      File.open(conf_file, 'w') do |fd|
        fd.write(YAML.dump(cfg))
      end
      puts "Generated configuration file for agent #{options[:agent]}:"
      puts "  - config: #{conf_file}"
        
      if options[:monit]
        pid_file = Nanite::PidFile.new("#{options[:pid_prefix]}-#{cfg[:identity]}", :pid_dir => cfg[:pid_dir])
        if File.exists?("/etc/monit.d") 
          monit_config_file = File.join("/etc/monit.d", "#{options[:agent]}-#{options[:identity]}-monit.conf")
        else
          monit_config_file = File.join(agent_dir, "#{options[:agent]}-#{options[:identity]}-monit.conf")
        end
        start_prog = "/usr/bin/rnac --start #{options[:agent]}"
        stop_prog = "/usr/bin/rnac --kill #{pid_file}"
        setup_monit(options[:agent], pid_file, monit_config_file, start_prog, stop_prog) 
        puts "  - monit config: #{monit_config_file}"
      end
    end

    # Create options hash from command line arguments
    def parse_args
      options = {}
      options[:agent] = ARGV[0]
      options[:options] = {}
      fail('No agent specified on the command line.', print_usage=true) if options[:agent].nil?

      opts = OptionParser.new do |opts|
        parse_common(opts, options)

       opts.on('-a', '--actors-dir DIR') do |d|
         options[:actors_dir] = d
       end

       opts.on('-z', '--pid-dir DIR') do |d|
         options[:pid_dir] = d
       end

       opts.on('-w', '--monit') do
         options[:monit] = true
       end

       opts.on('-o', '--options OPT') do |e|
         fail("Invalid option definition '#{e}' (use '=' to separate name and value)") unless e.include?('=')
         key, val = e.split(/=/)
         options[:options][key.to_sym] = val
       end

       opts.on_tail('--help') do
          RDoc::usage_from_file(__FILE__)
          exit
        end
      end

      opts.parse!(ARGV)
      resolve_identity(options)
      options
    end

protected

    # Print error on console and exit abnormally
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      RDoc::usage_from_file(__FILE__) if print_usage      
      exit(1)
    end

    # Create monit configuration file
    def setup_monit(agent, pidfile, monit_config_file, start_prog, stop_prog)
      File.open(monit_config_file, "w") do |f|
        f.puts "check process #{agent} "
        f.puts "\twith pidfile \"#{pidfile}\""
        f.puts "\tstart program \"#{start_prog}\""
        f.puts "\tstop program \"#{stop_prog}\""
      end
      # monit requires strict perms on this file
      File.chmod 0600, monit_config_file
    end

    def config_file(agent)
      File.join(gen_agent_dir(agent), 'config.yml')
    end
    
    def agent_config(agent)
      file = File.join(agent_dir(agent), "#{agent}.yml")
      return nil unless File.exist?(file)
      symbolize(YAML.load(IO.read(file))) rescue nil
    end

    # Version information
    def version
      "rad #{VERSION.join('.')} - RightScale Agent Deployer (c) 2009 RightScale"
    end

  end
end
