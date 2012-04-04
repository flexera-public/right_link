# === Synopsis:
#   RightScale Agent Controller (rnac) - (c) 2009-2011 RightScale Inc
#
#   rnac is a command line tool for managing a RightLink agent
#
# === Examples:
#   Start new agent named AGENT:
#     rnac --start AGENT
#     rnac -s AGENT
#
#   Stop running agent named AGENT:
#     rnac --stop AGENT
#     rnac -p AGENT
#
#   Stop agent with given serialized ID:
#     rnac --stop-agent ID
#
#   Terminate all agents on local machine:
#     rnac --killall
#     rnac -K
#
#   List agents configured on local machine:
#     rnac --list
#     rnac -l
#
#   List status of agents configured on local machine:
#     rnac --status
#     rnac -U
#
#   Start new agent named AGENT in foreground:
#     rnac --start AGENT --foreground
#     rnac -s AGENT -f
#
#   Start new agent named AGENT of type TYPE:
#     rnac --start AGENT --type TYPE
#     rnac -s AGENT -t TYPE
#
#   Note: To start multiple agents of the same type generate one
#         config.yml file with rad and then start each agent with rnac:
#         rad my_agent
#         rnac -s my_agent_1 -t my_agent
#         rnac -s my_agent_2 -t my_agent
#
# === Usage:
#    rnac [options]
#
#    options:
#      --start, -s AGENT          Start agent named AGENT
#      --stop, -p AGENT           Stop agent named AGENT
#      --stop-agent ID            Stop agent with serialized identity ID
#      --kill, -k PIDFILE         Kill process with given process id file
#      --killall, -K              Stop all running agents
#      --decommission, -d [AGENT] Send decommission signal to instance agent named AGENT,
#                                 defaults to 'instance'
#      --shutdown, -S [AGENT]     Send a terminate request to agent named AGENT,
#                                 defaults to 'instance'
#      --status, -U               List running agents on local machine
#      --identity, -i ID          Use base id ID to build agent's identity
#      --token, -t TOKEN          Use token TOKEN to build agent's identity
#      --prefix, -x PREFIX        Use prefix PREFIX to build agent's identity
#      --type TYPE                Use agent type TYPE to build agent's' identity,98589
#                                 defaults to AGENT with any trailing '_[0-9]+' removed
#      --list, -l                 List all configured agents
#      --user, -u USER            Set AMQP user
#      --pass, -p PASS            Set AMQP password
#      --vhost, -v VHOST          Set AMQP vhost
#      --host, -h HOST            Set AMQP server hostname
#      --port, -P PORT            Set AMQP server port
#      --cfg-dir, -c DIR          Set directory containing configuration for all agents
#      --pid-dir, -z DIR          Set directory containing agent process id files
#      --log-dir DIR              Set log directory
#      --log-level LVL            Log level (debug, info, warning, error or fatal)
#      --foreground, -f           Run agent in foreground
#      --interactive, -I          Spawn an irb console after starting agent
#      --test                     Use test settings
#      --help                     Display help

require 'rubygems'
require 'right_agent/scripts/agent_controller'

module RightScale

  class RightLinkAgentController < AgentController

    # Create and run controller
    #
    # === Return
    # true:: Always return true
    def self.run
      c = RightLinkAgentController.new
      c.control(c.parse_args)
    rescue Errno::EACCES => e
      STDERR.puts e.message
      STDERR.puts "Try elevating privilege (sudo/runas) before invoking this command."
      exit(2)
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
      opts.on("-d", "--decommission [AGENT]") do |a|
        options[:action] = 'decommission'
        options[:agent_name] = a || 'instance'
        options[:thin_command_client] = true
      end

      opts.on("-S", "--shutdown [AGENT]") do |a|
        options[:action] = 'shutdown'
        options[:agent_name] = a || 'instance'
        options[:thin_command_client] = true
      end

      opts.on('--help') do
        puts Usage.scan(__FILE__)
        exit
      end
    end

    # Decommission instance agent
    #
    # === Parameters
    # agent_name(String):: Agent name
    #
    # === Return
    # (Boolean):: true if process was decommissioned, otherwise false
    def decommission_agent(agent_name)
      run_command('Decommissioning...', 'decommission')
    end

    # Shutdown instance agent
    #
    # === Parameters
    # agent_name(String):: Agent name
    #
    # === Return
    # (Boolean):: true if process was shutdown, otherwise false
    def shutdown_agent(agent_name)
      run_command('Shutting down...', 'terminate')
    end

    # Trigger execution of given command in instance agent and wait for it to be done
    #
    # === Parameters
    # message(String):: Console display message
    # command(String):: Command name
    #
    # === Return
    # (Boolean):: true if command executed successfully, otherwise false
    def run_command(message, command)
      options = AgentConfig.agent_options(@options[:agent_name])
      listen_port = options[:listen_port]
      unless listen_port
        $stderr.puts "Could not retrieve listen port for agent #{@options[:identity]}"
        return false
      end
      puts message
      begin
        @client = CommandClient.new(listen_port, options[:cookie])
        @client.send_command({ :name => command }, verbose = false, timeout = 100) { |r| puts r }
      rescue Exception => e
        $stderr.puts Log.format("Failed or else time limit was exceeded, confirm that local instance is still running", e, :trace)
        return false
      end
      true
    end

    # Determine syslog program name based on options
    #
    # === Parameters
    # options(Hash):: Command line options
    #
    # === Return
    # (String):: Program name
    def syslog_program_name(options)
      'RightLink'
    end

  end # RightLinkAgentController

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
