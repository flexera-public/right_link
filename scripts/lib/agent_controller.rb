# === Synopsis:
#   RightScale Nanite Controller (rnac) - (c) 2009 RightScale
#
#   rnac is a command line tool that allows managing RightScale agents.
#
# === Examples:
#   Start new agent:
#     rnac --start AGENT
#     rnac -s AGENT
#
#   Stop running agent:
#     rnac --stop AGENT
#     rnac -p AGENT
#
#   Create agent configuration file and start it:
#     rnac --start AGENT --create_conf
#     rnac -s AGENT -c
#
#   Terminate agent with given ID token:
#     rnac --term-agent ID
#     rnac -T ID
#
#   Terminate all agents:
#     rnac --killall
#     rnac -K
#
#   List running agents on /right_net vhost on local machine:
#     rnac --status --vhost /right_net
#     rnac -U -v /right_net
#
#   Start new agent in foreground:
#     rnac --start AGENT --foreground
#     rnac -s AGENT -f
#
# === Usage:
#    rnac [options]
#
#    options:
#      --start, -s AGENT:   Start agent AGENT
#      --stop, -p AGENT:    Stop agent AGENT
#      --term-agent, -T ID: Stop agent with given serialized identity
#      --kill, -k PIDFILE:  Kill process with given pid file
#      --killall, -K:       Stop all running agents
#      --status, -U:        List running agents on local machine
#      --decommission, -d:  Send decommission signal to instance agent
#      --shutdown, -S:      Sends a terminate request to instance agent
#      --identity, -i ID    Use base id ID to build agent's identity
#      --token, -t TOKEN    Use token TOKEN to build agent's identity
#      --prefix, -r PREFIX  Prefix agent's identity with PREFIX
#      --list, -l:          List all registered agents
#      --user, -u USER:     Set AMQP user
#      --pass, -p PASS:     Set AMQP password
#      --vhost, -v VHOST:   Set AMQP vhost
#      --host, -h HOST:     Set AMQP server hostname
#      --port, -P PORT:     Set AMQP server port
#      --log-level LVL:     Log level (debug, info, warning, error or fatal)
#      --log-dir DIR:       Log directory
#      --pid-dir DIR:       Pid files directory (/tmp by default)
#      --alias ALIAS:       Run as alias of given agent (i.e. use different config but same name as alias)
#      --foreground, -f:    Run agent in foreground
#      --interactive, -I:   Spawn an irb console after starting agent
#      --test:              Use test settings
#      --version, -v:       Display version information
#      --help:              Display help

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
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'instance', 'instance_state'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'actors', 'lib', 'agent_manager'))

module RightScale

  class AgentController

    include Utils
    include CommonParser

    VERSION = [0, 2]
    YAML_EXT = %w{ yml yaml }
    FORCED_OPTIONS =
    {
      :format => :secure,
      :threadpool_size => 1
    }
    DEFAULT_OPTIONS =
    {
      :single_threaded => true,
      :log_dir => RightLinkConfig[:platform].filesystem.log_dir,
      :daemonize => true
    }

    @@agent = nil

    # Convenience wrapper
    def self.run
      c = AgentController.new
      c.control(c.parse_args)
    end

    # Parse arguments and run
    def control(options)
      # Validate arguments
      action = options.delete(:action)
      fail("No action specified on the command line.", print_usage=true) if action.nil?
      if action == 'kill' && (options[:pid_file].nil? || !File.file?(options[:pid_file]))
        fail("Missing or invalid pid file #{options[:pid_file]}", print_usage=true)
      end
      if options[:pid_dir] && !File.directory?(options[:pid_dir])
        File.makedirs(options[:pid_dir])
      end
      if options[:agent]
        root_dir = gen_agent_dir(options[:agent])
        fail("Deployment directory #{root_dir} is missing.") if !File.directory?(root_dir)
        cfg = File.join(root_dir, 'config.yml')
        fail("Deployment is missing configuration file in #{root_dir}.") unless File.exists?(cfg)
        file_options = symbolize(YAML.load(IO.read(cfg))) rescue {} || {}
        file_options.merge!(options)
        options = file_options
        RightLinkLog.program_name = syslog_program_name(options)
        RightLinkLog.log_to_file_only(options[:log_to_file_only])
        configure_proxy(options[:http_proxy], options[:no_http_proxy]) if options[:http_proxy]
      end 
      options.merge!(FORCED_OPTIONS)
      options_with_default = {}
      DEFAULT_OPTIONS.each { |k, v| options_with_default[k] = v }
      options = options_with_default.merge(options)
      @options = options

      # Start processing
      success = case action
      when /show|killall/
        action = 'stop' if action == 'killall'
        s = true
        running_agents.each { |id| s &&= run_cmd(action, id) }
        s
      when 'kill'
        kill_process
      else
        run_cmd(action, options[:identity])
      end

      exit(1) unless success
    end

    # Parse arguments
    def parse_args
      # The options specified in the command line will be collected in 'options'
      options = {}

      opts = OptionParser.new do |opts|
        parse_common(opts, options)
        parse_other_args(opts, options)

        opts.on("-s", "--start AGENT") do |a|
          options[:action] = 'run'
          options[:agent] = a
        end

        opts.on("-p", "--stop AGENT") do |a|
          options[:action] = 'stop'
          options[:agent] = a
        end

        opts.on("-T", "--term-agent ID") do |id|
          options[:action] = 'stop'
          options[:identity] = id
        end

        opts.on("-k", "--kill PIDFILE") do |file|
          options[:pid_file] = file
          options[:action] = 'kill'
        end
    
        opts.on("-K", "--killall") do
          options[:action] = 'killall'
        end

        opts.on("-d", "--decommission") do
          options[:action] = 'decommission'
        end

        opts.on("-U", "--status") do
          options[:action] = 'show'
        end

        opts.on("-l", "--list") do
          res =  available_agents
          if res.empty?
            puts "Found no registered agent"
          else
            puts version
            puts "Available agents:"
            res.each { |a| puts "  - #{a}" }
          end
          exit
        end

        opts.on("--log-level LVL") do |lvl|
          options[:log_level] = lvl
        end

        opts.on("--log-dir DIR") do |dir|
          options[:log_dir] = dir

          # ensure log directory exists (for windows, etc.)
          FileUtils.mkdir_p(options[:log_dir]) unless File.directory?(options[:log_dir])
        end

        opts.on("--pid-dir DIR") do |dir|
          options[:pid_dir] = dir
        end

        opts.on("-f", "--foreground") do
          options[:daemonize] = false
          #Squelch Ruby VM warnings about various things 
          $VERBOSE = nil
        end

        opts.on("-I", "--interactive") do
          options[:console] = true
        end

        opts.on("-S", "--shutdown") do
          options[:action] = 'shutdown'
        end

        opts.on("--help") do
          RDoc::usage_from_file(__FILE__)
        end

      end

      begin
        opts.parse(ARGV)
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

    # Dispatch action
    def run_cmd(action, id)
      # setup the environment from config if necessary
      begin
        case action
          when 'run'          then start_agent
          when 'stop'         then stop_agent(id)
          when 'show'         then show_agent(id)
          when 'decommission' then run_command(id, 'Decommissioning...', 'decommission')
          when 'shutdown'     then run_command(id, 'Shutting down...', 'terminate')
        end
      rescue SystemExit
        true
      rescue SignalException
        true
      rescue Exception => e
        msg = "Failed to #{action} #{name} (#{e.class.to_s}: #{e.message})" + "\n" + e.backtrace.join("\n")
        puts msg
      end
    end

    # Kill process defined in pid file
    def kill_process(sig='TERM')
      content = IO.read(@options[:pid_file])
      pid = content.to_i
      fail("Invalid pid file content '#{content}'") if pid == 0
      begin
        Process.kill(sig, pid)
      rescue Errno::ESRCH => e
        fail("Could not find process with pid #{pid}")
      rescue Errno::EPERM => e
        fail("You don't have permissions to stop process #{pid}")
      rescue Exception => e
        fail(e.message)
      end
      true
    end

    # Print failure message and exit abnormally
    def fail(message, print_usage=false)
      puts "** #{message}"
      RDoc::usage_from_file(__FILE__) if print_usage
      exit(1)
    end

    # Trigger execution of given command in instance agent and wait for it to be done.
    def run_command(id, msg, name)
      agent_name = AgentIdentity.parse(id).agent_name rescue 'instance'
      unless agent_name
        puts "Invalid agent identity #{id}"
        return false
      end
      options = agent_options(agent_name)
      listen_port = options[:listen_port]
      unless listen_port
        puts "Failed to retrieve listen port for agent #{id}"
        return false
      end
      puts msg
      begin
        @client = CommandClient.new(listen_port, options[:cookie])
        @client.send_command({ :name => name }, verbose=false, timeout=100) { |r| puts r }
      rescue Exception => e
        puts "Failed or else time limit was exceeded (#{e.message}).\nConfirm that the local instance is still running.\n#{e.backtrace.join("\n")}"
        return false
      end
      true
    end

    # Start agent, return true
    def start_agent
      begin
        @options[:root] = gen_agent_dir(@options[:agent])

        # Register exception handler
        @options[:exception_callback] = lambda { |e, msg, _| AgentManager.process_exception(e, msg) }

        # Override default status proc for windows instance since "uptime" is not available.
        if RightLinkConfig[:platform].windows?
          @options[:status_proc] = lambda { 1 }
        end

        puts "#{name} being started"

        EM.error_handler do |e|
          msg = "EM block execution failed with exception: #{e.message}"
          RightLinkLog.error(msg + "\n" + e.backtrace.join("\n"))
          RightLinkLog.error("\n\n===== Exiting due to EM block exception =====\n\n")
          EM.stop
        end

        EM.run do
          @@agent = Agent.start(@options)
        end

      rescue SystemExit
        raise # Let parents of forked (daemonized) processes die
      rescue Exception => e
        puts "#{name} failed with: #{e.message} in \n#{e.backtrace.join("\n")}"
      end
      true
    end
    
    # Stop given agent, return true on success, false otherwise
    def stop_agent(id)
      if @options[:agent]
        try_kill(agent_pid_file(@options[:agent]))
      else
        try_kill(agent_pid_file_from_id(@options, id))
      end
    end
    
    # Show status of given agent, return true on success, false otherwise
    def show_agent(id)
      if @options[:agent]
        show(pid_file) if pid_file = agent_pid_file(@options[:agent])
      else
        show(agent_pid_file_from_id(@options, id))
      end
    end

    # Human readable name for managed entity
    def name
      "Agent #{@options[:agent] + ' ' if @options[:agent]}with ID #{@options[:identity]}"
    end

    # Kill process with pid in given pid file
    def try_kill(pid_file)
      res = false
      if pid = pid_file.read_pid[:pid]
        begin
          Process.kill('TERM', pid)
          res = true
          puts "#{name} stopped."
        rescue Errno::ESRCH
          puts "#{name} not running."
        end
      else
        if File.file?(pid_file.to_s)
          puts "Invalid pid file '#{pid_file.to_s}' content: #{IO.read(pid_file.to_s)}"
        else
          puts "Non-existent pid file '#{pid_file.to_s}'"
        end
      end
      res
    end

    # Show status of process with pid in given pid file
    def show(pid_file)
      res = false
      if pid = pid_file.read_pid[:pid]
        pid = Process.getpgid(pid) rescue -1
        if pid != -1
          psdata = `ps up #{pid}`.split("\n").last.split
          memory = (psdata[5].to_i / 1024)
          puts "#{name} is alive, using #{memory}MB of memory"
          res = true
        else
          puts "#{name} is not running but has a stale pid file at #{pid_file}"
        end
      end
      res
    end

    # Serialized identity for running RightScale agents
    # based on existence of RabbitMQ queue
    def running_agents
      list = `rabbitmqctl list_queues -p #{@options[:vhost]}`
      list.scan(/^\s*rs-instance([\S]+)/).flatten +
      list.scan(/^\s*rs-proxy([\S]+)/).flatten +
      list.scan(/^\s*rs-core([\S]+)/).flatten
    end

    # Available agents i.e. agents that have a config file in the 'agents' dir
    def available_agents
      agents_configs.map { |cfg| File.basename(cfg, '.*') }
    end

    # List of all agents configuration files
    def agents_configs
      Dir.glob(File.join(agents_dir, "**", "*.{#{YAML_EXT.join(',')}}"))
    end

    # Determine syslog program name based on options
    def syslog_program_name(options)
      'RightLink'
    end

    # Enable the use of an HTTP proxy for this process and its subprocesses
    def configure_proxy(proxy_setting, exceptions)
      ENV['HTTP_PROXY'] = proxy_setting
      ENV['http_proxy'] = proxy_setting
      ENV['NO_PROXY']   = exceptions
      ENV['no_proxy']   = exceptions
    end

    # Version information
    def version
      "rnac #{VERSION.join('.')} - RightScale Nanite Controller (c) 2009 RightScale"
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
