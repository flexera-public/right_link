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

module RightScale

  # Commands exposed by instance agent
  # To add a new command, simply add it to the COMMANDS hash and define its implementation in
  # a method called '<command name>_command'
  class InstanceCommands

    # List of command names associated with description
    # The commands should be implemented in methods in this class named '<name>_command'
    # where <name> is the name of the command.
    COMMANDS = {
      :list             => 'List all available commands with their description',
      :run_recipe       => 'Run recipe with id given in options[:id] and optionally JSON given in options[:json]',
      :run_right_script => 'Run RightScript with id given in options[:id] and arguments given in hash options[:arguments] (e.g. { \'application\' => \'text:Mephisto\' })',
      :set_log_level    => 'Set log level to options[:level]',
      :get_log_level    => 'Get log level',
      :decommission     => 'Run instance decommission bundle synchronously',
      :terminate        => 'Terminate agent',
      :get_tags         => 'Retrieve instance tags',
      :add_tag          => 'Add given tag',
      :remove_tag       => 'Remove given tag',
      :test_ack         => 'Send messages to core agent to test message acks',
      :test_persistent  => 'Send messages to core agent to test persistent handling',
      :test_freshness   => 'Send message to core agent to test freshness'
    }

    # Build hash of commands associating command names with block
    #
    # === Parameters
    # agent_identity(String):: Serialized instance agent identity
    # scheduler(InstanceScheduler):: Scheduler used by decommission command
    #
    # === Return
    # cmds(Hash):: Hash of command blocks keyed by command names
    def self.get(agent_identity, scheduler)
      cmds = {}
      target = new(agent_identity, scheduler)
      COMMANDS.each { |k, v| cmds[k] = lambda { |opts, conn| opts[:conn] = conn; target.send("#{k.to_s}_command", opts) } }
      cmds
    end

    # Set token id used to send core requests
    #
    # === Parameter
    # token_id(String):: Instance token id
    # scheduler(InstanceScheduler):: Scheduler used by decommission command
    def initialize(agent_identity, scheduler)
      @agent_identity = agent_identity
      @scheduler = scheduler
    end

    protected

    # List command implementation
    #
    # === Parameters
    # opts(Hash):: Should contain the connection for sending data
    #
    # === Return
    # true:: Always return true
    def list_command(opts)
      usage = "Agent exposes the following commands:\n"
      COMMANDS.reject { |k, _| k == :list || k.to_s =~ /test/ }.each do |c|
        c.each { |k, v| usage += " - #{k.to_s}: #{v}\n" }
      end
      CommandIO.instance.reply(opts[:conn], usage)
    end

    # Run recipe command implementation
    #
    # === Return
    # true:: Always return true
    def run_recipe_command(opts)
      send_request('/forwarder/schedule_recipe', opts[:conn], opts[:options])
    end

    # Run RightScript command implementation
    #
    # === Return
    # true:: Always return true
    def run_right_script_command(opts)
      send_request('/forwarder/schedule_right_script', opts[:conn], opts[:options])
    end

    # Set log level command
    #
    # === Return
    # true:: Always return true
    def set_log_level_command(opts)
      RightLinkLog.level = opts[:level] if [ :debug, :info, :warn, :error, :fatal ].include?(opts[:level])
      CommandIO.instance.reply(opts[:conn], RightLinkLog.level)
    end

    # Get log level command
    #
    # === Return
    # true:: Always return true
    def get_log_level_command(opts)
      CommandIO.instance.reply(opts[:conn], RightLinkLog.level)
    end

    # Decommission command
    #
    # === Return
    # true
    def decommission_command(opts)
      @scheduler.run_decommission { CommandIO.instance.reply(opts[:conn], "Decommissioned") }
    end

    # Terminate command
    #
    # === Return
    # true
    def terminate_command(opts)
      CommandIO.instance.reply(opts[:conn], "Terminating")
      @scheduler.terminate
    end

    # Get tags command
    #
    # === Return
    # true
    def get_tags_command(opts)
      RightScale::AgentTagsManager.instance.tags { |t| CommandIO.instance.reply(opts[:conn], t) }
    end

    # Add given tag
    #
    # === Return
    # true
    def add_tag_command(opts)
      RightScale::AgentTagsManager.instance.add_tags(opts[:tag])
      CommandIO.instance.reply(opts[:conn], "Request to add tag '#{opts[:tag]}' sent successfully.")
    end

    # Remove given tag
    #
    # === Return
    # true
    def remove_tag_command(opts)
      RightScale::AgentTagsManager.instance.remove_tags(opts[:tag])
      CommandIO.instance.reply(opts[:conn], "Request to remove tag '#{opts[:tag]}' sent successfully.")
    end

    # Repeatedly push test_ack command to core agent tester
    #
    # === Parameters
    # opts(Hash):: Options:
    #   :conn(EM::Connection):: Connection used to send reply
    #   :options(Hash):: Test command payload and options:
    #     :index(Integer):: Starting index for iteration, defaults to 0
    #     :times(Integer):: Number of times to send message
    #     :exit(Integer):: Index at which core agent is to exit
    #
    # === Return
    # true:: Always return true
    def test_ack_command(opts)
      options = opts[:options].dup
      options[:agent_identity] = @agent_identity
      options[:index] ||= 0
      exit_index = options[:exit]
      options[:times].times do
        options[:exit] = (options[:index] == exit_index)
        RightLinkLog.info("Sending test_ack, index = #{options[:index]} exit = #{options[:exit]}")
        MapperProxy.instance.push("/tester/test_ack", options, options)
        options[:index] += 1
      end
      CommandIO.instance.reply(opts[:conn], "Finished sending #{options[:times]} test_ack's")
    end

    # Repeatedly send test_persistent request to core agent tester and receive response
    #
    # === Parameters
    # opts(Hash):: Options:
    #   :conn(EM::Connection):: Connection used to send reply
    #   :options(Hash):: Test command payload and options:
    #     :index(Integer):: Starting index for iteration, defaults to 0
    #     :times(Integer):: Number of times to send message
    #     :target(String):: Serialized identity of instance agent being targeted
    #
    # === Return
    # true:: Always return true
    def test_persistent_command(opts)
      options = opts[:options].dup
      options[:agent_identity] = @agent_identity
      options[:index] ||= 0
      options[:times].times do
        RightLinkLog.info("Sending test_persistent request, index = #{options[:index]}")
        MapperProxy.instance.request("/tester/test_persistent", options, options) do |res|
          res = RightScale::OperationResult.from_results(res)
          RightScale::RightLinkLog.info("Received test_persistent response, index = #{res.content} " +
                                        "status = #{res.status_code}")
        end
        options[:index] += 1
      end
      CommandIO.instance.reply(opts[:conn], "Finished sending #{options[:times]} test_persistent's")
    end

    # Repeatedly send test_freshness request to core agent tester and receive response
    #
    # === Parameters
    # opts(Hash):: Options:
    #   :conn(EM::Connection):: Connection used to send reply
    #   :options(Hash):: Test command payload and options:
    #     :index(Integer):: Starting index for iteration, defaults to 0
    #     :times(Integer):: Number of times to send message
    #     :kill(Integer):: Id of process to be killed, if any
    #
    # === Return
    # true:: Always return true
    def test_freshness_command(opts)
      options = opts[:options].dup
      options[:agent_identity] = @agent_identity
      options[:index] ||= 0
      options[:times].times do
        RightLinkLog.info("Sending test_freshness request, index = #{options[:index]}")
        MapperProxy.instance.request("/tester/test_freshness", options, options) do |res|
          res = RightScale::OperationResult.from_results(res)
          RightScale::RightLinkLog.info("Received test_freshness response, index = #{res.content} " +
                                        "status = #{res.status_code}")
        end
        options[:index] += 1
      end
      CommandIO.instance.reply(opts[:conn], "Finished sending #{options[:times]} test_freshness's")
    end

    # Helper method that sends given request and report status through command IO
    #
    # === Parameters
    # request(String):: Request that should be sent
    # conn(EM::Connection):: Connection used to send reply
    # options(Hash):: Request options
    #
    # === Return
    # true:: Always return true
    def send_request(request, conn, options)
      options[:agent_identity] = @agent_identity
      RightScale::RequestForwarder.request(request, options) do |r|
        res = OperationResult.from_results(r)
        CommandIO.instance.reply(conn, res.success? ? 'Request sent successfully' : "Request failed: #{res.content}")
      end
      true
    end

  end

end
