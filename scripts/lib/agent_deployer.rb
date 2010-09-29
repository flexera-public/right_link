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
# === Usage:
#    rad AGENT [options]
#
#    options:
#      --identity, -i ID        Use base id ID to build agent's identity
#      --shared-queue, -q QUEUE Use QUEUE as input for agent in addition to identity queue
#      --token, -t TOKEN        Use token TOKEN to build agent's identity
#      --secure-identity, -S    Derive actual token from given TOKEN and ID
#      --prefix, -r PREFIX      Prefix agent identity with PREFIX
#      --url                    Set agent AMQP connection URL (host, port, user, pass, vhost)
#      --user, -u USER          Set agent AMQP username
#      --password, -p PASS      Set agent AMQP password
#      --vhost, -v VHOST        Set agent AMQP virtual host
#      --port, -P PORT          Set AMQP broker port
#      --host, -h HOST          Set AMQP broker host
#      --alias ALIAS            Use alias name for identity and base config
#      --pid-dir, -z DIR        Set directory containing pid file
#      --monit, -w              Generate monit configuration file
#      --options, -o KEY=VAL    Pass-through options
#      --http-proxy, -P PROXY   Use a proxy for all agent-originated HTTP traffic
#      --no-http-proxy          Comma-separated list of proxy exceptions
#      --fresh-timeout SEC      Set maximum age in seconds before a request times out and is rejected
#      --retry-timeout SEC      Set maximum number of seconds to retry request before give up
#      --retry-interval SEC     Set number of seconds before initial request retry, increases exponentially
#      --check-interval SEC     Set number of seconds between failed connection checks, increases exponentially
#      --grace-timeout SEC      Set number of seconds before graceful termination times out
#      --[no-]dup-check         Set whether to check for and reject duplicate requests, .e.g., due to retries
#      --persist SET            Set default handling for persistence of messages being sent via AMQP
#                               (none, all, push, or request)
#      --prefetch COUNT         Set maximum requests AMQP broker is to prefetch before current is ack'd
#      --actors-dir DIR         Set directory containing actor classes
#      --agents-dir DIR         Set directory containing agent configuration
#      --test                   Build test deployment using default test settings
#      --quiet, -Q              Do not produce output
#      --help                   Display help
#      --version                Display version information

require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'yaml'
require 'ftools'
require 'fileutils'
require File.join(File.dirname(__FILE__), 'rdoc_patch')
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.join(File.dirname(__FILE__), 'agent_utils')
require File.join(File.dirname(__FILE__), 'common_parser')
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))

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
      agent = options[:alias] || options[:agent]
      options[:agents_dir] ||= agent_dir(agent)
      options[:actors_dir] ||= actors_dir
      cfg = agent_config(options[:agents_dir], agent)
      fail("Cannot read configuration for agent #{options[:agent]}") unless cfg
      actors = cfg.delete(:actors)
      fail('Agent configuration does not define actors') unless actors && actors.respond_to?(:each)
      actors.each do |actor|
        actor_file = File.join(options[:actors_dir], "#{actor}.rb")
        fail("Cannot find actor file '#{actor_file}'") unless File.exists?(actor_file)
      end
      options[:actors] = actors
      options[:initrb] = File.join(options[:agents_dir], "#{agent}.rb")
      write_config(options)
    end

    # Generate configuration files
    def write_config(options)
      cfg = {}
      cfg[:identity]        = options[:identity] if options[:identity]
      cfg[:shared_queue]    = options[:shared_queue] if options[:shared_queue]
      cfg[:pid_dir]         = options[:pid_dir] || RightScale::RightLinkConfig[:platform].filesystem.pid_dir
      cfg[:user]            = options[:user] if options[:user]
      cfg[:pass]            = options[:pass] if options[:pass]
      cfg[:vhost]           = options[:vhost] if options[:vhost]
      cfg[:port]            = options[:port] if options[:port]
      cfg[:host]            = options[:host] if options[:host]
      cfg[:initrb]          = options[:initrb] if options[:initrb]
      cfg[:actors]          = options[:actors] if options[:actors]
      cfg[:actors_dir]      = options[:actors_dir] if options[:actors_dir]
      cfg[:format]          = 'secure'
      cfg[:prefetch]        = options[:prefetch] || 1
      cfg[:persist]         = options[:persist] || 'push'
      cfg[:fresh_timeout]   = options[:fresh_timeout] || 15 * 60
      cfg[:retry_timeout]   = options[:retry_timeout] || 10 * 60
      cfg[:retry_interval]  = options[:retry_interval] || 30
      cfg[:check_interval]  = options[:check_interval] if options[:check_interval]
      cfg[:grace_timeout]   = options[:grace_timeout] if options[:grace_timeout]
      cfg[:dup_check]       = options[:dup_check].nil? ? true : options[:dup_check]
      cfg[:http_proxy]      = options[:http_proxy] if options[:http_proxy]
      cfg[:no_http_proxy]   = options[:no_http_proxy] if options[:no_http_proxy]
      options[:options].each { |k, v| cfg[k] = v } if options[:options]

      gen_dir = gen_agent_dir(options[:agent])
      File.makedirs(gen_dir) unless File.exists?(gen_dir)
      cfg_file = config_file(options[:agent])
      File.delete(cfg_file) if File.exists?(cfg_file)
      File.open(cfg_file, 'w') { |fd| fd.puts "# Created at #{Time.now}" }
      File.open(cfg_file, 'a') do |fd|
        fd.write(YAML.dump(cfg))
      end
      unless options[:quiet]
        puts "Generated configuration file for agent #{options[:agent]}:"
        puts "  - config: #{cfg_file}"
      end

      if options[:monit]
        cfg_file = setup_monit(options)
        puts "  - monit config: #{cfg_file}" unless options[:quiet]
      end
    end

    # Create options hash from command line arguments
    def parse_args
      options = {}
      options[:agent] = ARGV[0]
      options[:options] = { :secure => true }
      options[:quiet] = false
      fail('No agent specified on the command line.', print_usage=true) if options[:agent].nil?

      opts = OptionParser.new do |opts|
        parse_common(opts, options)
        parse_other_args(opts, options)

        opts.on('-S', '--secure-identity') do
          options[:secure_identity] = true
        end

        opts.on('-q', '--shared-queue QUEUE') do |q|
          options[:shared_queue] = q
        end

        opts.on('-z', '--pid-dir DIR') do |d|
          options[:pid_dir] = d
        end

        opts.on('-w', '--monit') do
          options[:monit] = true
        end

        opts.on('-P', '--http-proxy PROXY') do |proxy|
          options[:http_proxy] = proxy
        end

        opts.on('--no-http-proxy NOPROXY') do |no_proxy|
          options[:no_http_proxy] = no_proxy
        end

        opts.on('--fresh-timeout SEC') do |sec|
          options[:fresh_timeout] = sec.to_i
        end

        opts.on('--retry-timeout SEC') do |sec|
          options[:retry_timeout] = sec.to_i
        end

        opts.on('--retry-interval SEC') do |sec|
          options[:retry_interval] = sec.to_i
        end

        opts.on('--check-interval SEC') do |sec|
          options[:check_interval] = sec.to_i
        end

        opts.on('--grace-timeout SEC') do |sec|
          options[:grace_timeout] = sec.to_i
        end

        opts.on('--[no-]dup-check') do |b|
          options[:dup_check] = b
        end

        opts.on('--persist SET') do |set|
          options[:persist] = set
        end

        opts.on('--prefetch COUNT') do |count|
          options[:prefetch] = count.to_i
        end

        opts.on('--actors-dir DIR') do |d|
          options[:actors_dir] = d
        end

        opts.on('--agents-dir DIR') do |d|
          options[:agents_dir] = d
        end

        opts.on('-o', '--options OPT') do |e|
          fail("Invalid option definition '#{e}' (use '=' to separate name and value)") unless e.include?('=')
          key, val = e.split(/=/)
          options[:options][key.gsub('-', '_').to_sym] = val
        end

        opts.on('-Q', '--quiet') do
          options[:quiet] = true
        end

        opts.on_tail('--help') do
          RDoc::usage_from_file(__FILE__)
          exit
        end
      end
      begin
        opts.parse!(ARGV)
      rescue Exception => e
        fail(e.message, print_usage = true)
      end
      resolve_identity(options)
      options
    end

    # Parse any other arguments used by agent
    def parse_other_args(opts, options)
    end

protected

    # Print error on console and exit abnormally
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      RDoc::usage_from_file(__FILE__) if print_usage
      exit(1)
    end

    # Create monit configuration file
    def setup_monit(options)
      agent = options[:agent]
      pid_file = PidFile.new("#{options[:identity]}", :pid_dir => options[:pid_dir] || RightScale::RightLinkConfig[:platform].filesystem.pid_dir)
      cfg_file = if File.exists?('/opt/rightscale/etc/monit.d')
        File.join('/opt/rightscale/etc/monit.d', "#{options[:identity]}.conf")
      else
        File.join(gen_agent_dir(agent), "#{options[:identity]}-monit.conf")
      end
      File.open(cfg_file, 'w') { |f| f.puts monit_config(agent, pid_file) }
      # monit requires strict perms on this file
      File.chmod 0600, cfg_file
      cfg_file
    end

    # Monit configuration file content
    def monit_config(agent, pid_file)
      config = <<-EOF
check process #{agent}
  with pidfile \"#{pid_file}\"
  start program \"/usr/bin/rnac --start #{agent}\"
  stop program \"/usr/bin/rnac --stop #{agent}\"
  mode manual
      EOF
    end

    def config_file(agent)
      File.join(gen_agent_dir(agent), 'config.yml')
    end

    def agent_config(agents_dir, agent)
      cfg_file = File.join(agents_dir, "#{agent}.yml")
      return nil unless File.exists?(cfg_file)
      symbolize(YAML.load(IO.read(cfg_file))) rescue nil
    end

    # Version information
    def version
      "rad #{VERSION.join('.')} - RightScale Agent Deployer (c) 2009 RightScale"
    end

  end
end

#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
