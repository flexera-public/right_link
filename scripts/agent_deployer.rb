# === Synopsis:
#   RightScale Agent Deployer (rad) - (c) 2009-2011 RightScale Inc
#
#   rad is a command line tool for building the configuration file for a RightLink agent
#
#   The configuration file is generated in:
#     <agent name>/config.yml
#   in platform-specific RightAgent configuration directory
#
# === Examples:
#   Build configuration for agent named AGENT with default options:
#     rad AGENT
#
#   Build configuration for agent named AGENT so it uses given AMQP settings:
#     rad AGENT --user USER --pass PASSWORD --vhost VHOST --port PORT --host HOST
#     rad AGENT -u USER -p PASSWORD -v VHOST -P PORT -h HOST
#
# === Usage:
#    rad AGENT [options]
#
#    options:
#      --root-dir, -r DIR       Set agent root directory (containing init, actors, and certs subdirectories)
#      --cfg-dir, -c DIR        Set directory where generated configuration files for all agents are stored
#      --pid-dir, -z DIR        Set directory containing process id file
#      --identity, -i ID        Use base id ID to build agent's identity
#      --token, -t TOKEN        Use token TOKEN to build agent's identity
#      --prefix, -x PREFIX      Use prefix PREFIX to build agent's identity
#      --type TYPE              Use agent type TYPE to build agent's' identity,
#                               defaults to AGENT with any trailing '_[0-9]+' removed
#      --secure-identity, -S    Derive actual token from given TOKEN and ID
#      --url                    Set agent AMQP connection URL (host, port, user, pass, vhost)
#      --user, -u USER          Set agent AMQP username
#      --password, -p PASS      Set agent AMQP password
#      --vhost, -v VHOST        Set agent AMQP virtual host
#      --host, -h HOST          Set AMQP broker host
#      --port, -P PORT          Set AMQP broker port
#      --prefetch COUNT         Set maximum requests AMQP broker is to prefetch before current is ack'd
#      --http-proxy PROXY       Use a proxy for all agent-originated HTTP traffic
#      --http-no-proxy NOPROXY  Comma-separated list of proxy exceptions (e.g. metadata server)
#      --time-to-live SEC       Set maximum age in seconds before a request times out and is rejected
#      --retry-timeout SEC      Set maximum number of seconds to retry request before give up
#      --retry-interval SEC     Set number of seconds before initial request retry, increases exponentially
#      --check-interval SEC     Set number of seconds between failed connection checks, increases exponentially
#      --ping-interval SEC      Set minimum number of seconds since last message receipt for the agent
#                               to ping the mapper to check connectivity, 0 means disable ping
#      --reconnect-interval SEC Set number of seconds between broker reconnect attempts
#      --offline-queueing, -q   Enable queuing of requests when lose broker connectivity
#      --grace-timeout SEC      Set number of seconds before graceful termination times out
#      --[no-]dup-check         Set whether to check for and reject duplicate requests, .e.g., due to retries
#      --options, -o KEY=VAL    Set options that act as final override for any persisted configuration settings
#      --monit, -m              Generate monit configuration file
#      --test                   Build test deployment using default test settings
#      --quiet, -Q              Do not produce output
#      --help                   Display help

require 'rubygems'
require 'right_agent/scripts/agent_deployer'

module RightScale

  class RightLinkAgentDeployer < AgentDeployer

    # Create and run deployer
    #
    # === Return
    # true:: Always return true
    def self.run
      d = RightLinkAgentDeployer.new
      d.deploy(d.parse_args)
    end

    protected

    # Parse other arguments used by infrastructure agents
    #
    # === Parameters
    # opts(OptionParser):: Options parser with options to be parsed
    # options(Hash):: Storage for options that are parsed
    #
    # === Return
    # true:: Always return true
    def parse_other_args(opts, options)
      opts.on('-q', '--offline-queueing') do
        options[:offline_queueing] = true
      end

      opts.on('--help') do
        puts Usage.scan(__FILE__)
        exit
      end
    end

    # Determine configuration settings to be persisted
    #
    # === Parameters
    # options(Hash):: Command line options
    # cfg(Hash):: Initial configuration settings
    #
    # === Return
    # cfg(Hash):: Configuration settings
    def configure(options, cfg)
      cfg = super(options, cfg)
      cfg[:offline_queueing] = options[:offline_queueing]
      cfg
    end

    # Setup agent monitoring
    #
    # === Parameters
    # options(Hash):: Command line options
    #
    # === Return
    # true:: Always return true
    def monitor(options)
      # Create monit file for running instance agent
      agent_name = options[:agent_name]
      identity = options[:identity]
      pid_file = PidFile.new(identity)
      cfg = <<-EOF
check process #{agent_name}
  with pidfile \"#{pid_file}\"
  start program \"/opt/rightscale/bin/rnac --start #{agent_name}\"
  stop program \"/opt/rightscale/bin/rnac --stop #{agent_name}\"
  mode manual
      EOF
      cfg_file = setup_monit(identity, options[:agent_name], cfg)
      puts "  - agent monit config: #{cfg_file}" unless options[:quiet]

      # Create monit file for running checker daemon to monitor monit and periodically check
      # whether the agent is communicating okay and if not, to trigger a re-enroll
      identity = "#{options[:identity]}-rchk"
      pid_file = PidFile.new(identity)
      cfg = <<-EOF
check process checker
  with pidfile \"#{pid_file}\"
  start program \"/opt/rightscale/bin/rchk --start --monit\"
  stop program \"/opt/rightscale/bin/rchk --stop\"
  mode manual
      EOF
      cfg_file = setup_monit(identity, options[:agent_name], cfg)
      puts "  - agent checker monit config: #{cfg_file}" unless options[:quiet]
      true
    end

    # Setup monit configuration
    def setup_monit(identity, name, cfg)
      cfg_file = if File.exists?('/opt/rightscale/etc/monit.d')
        File.join('/opt/rightscale/etc/monit.d', "#{identity}.conf")
      else
        File.join(AgentConfig.cfg_dir, name, "#{identity}.conf")
      end
      File.open(cfg_file, 'w') { |f| f.puts(cfg) }
      # monit requires strict perms on this file
      File.chmod(0600, cfg_file) # monit requires strict perms on this file
      cfg_file
    end

  end # RightLinkAgentDeployer

end # RightScale

#
# Copyright (c) 2009-2011 RightScale Inc
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
