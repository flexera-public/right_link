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
      :get_log_level    => 'Get log level'
    }

    # Build hash of commands associating command names with block
    #
    # === Parameters
    # agent_identity<String>:: Serialized instance agent identity
    #
    # === Return
    # cmds<Hash>:: Hash of command blocks keyed by command names
    def self.get(agent_identity)
      cmds = {}
      target = new(agent_identity)
      COMMANDS.each { |k, v| cmds[k] = lambda { |opts| target.send("#{k.to_s}_command", opts) } }
      cmds
    end

    # Set token id used to send core requests
    #
    # === Parameter
    # token_id<String>:: Instance token id
    def initialize(agent_identity)
      @agent_identity = agent_identity
    end

    protected

    # List command implementation
    #
    # === Parameters
    # opts<Hash>:: Should contain the instance command id
    #
    # === Return
    # true:: Always return true
    def list_command(opts)
      usage = "Agent exposes the following commands:\n"
      COMMANDS.reject { |c| c.include?(:list) }.each do |c|
        c.each { |k, v| usage += " - #{k.to_s}: #{v}\n" }
      end
      CommandIO.reply(opts[:port], usage)
    end

    # Run recipe command implementation
    #
    # === Return
    # true:: Always return true
    def run_recipe_command(opts)
      send_request('/forwarder/schedule_recipe', opts[:port], opts[:options])
    end

    # Run RightScript command implementation
    #
    # === Return
    # true:: Always return true
    def run_right_script_command(opts)
      send_request('/forwarder/schedule_right_script', opts[:port], opts[:options])
    end

    # Set log level command
    #
    # === Return
    # true:: Always return true
    def set_log_level_command(opts)
      log_level = case opts[:level]
        when :debug then Logger::DEBUG
        when :info  then Logger::INFO
        when :warn  then Logger::WARN
        when :error then Logger::ERROR
        when :fatal then Logger::FATAL
        else nil
      end
      RightLinkLog.level = log_level if log_level
      CommandIO.reply(opts[:port], RightLinkLog.level)
      true
    end

    # Get log level command
    #
    # === Return
    # true:: Always return true
    def get_log_level_command(opts)
      CommandIO.reply(opts[:port], RightLinkLog.level)
      true
    end

    # Helper method that sends given request and report status through command IO
    #
    # === Parameters
    # request<String>:: Request that should be sent
    # port<Integer>:: Port command line tool is listening on
    # options<Hash>:: Request options
    #
    # === Return
    # true:: Always return true
    def send_request(request, port, options)
      options[:agent_identity] = @agent_identity
      Nanite::MapperProxy.instance.request(request, options) do |r|
        res = OperationResult.from_results(r)
        CommandIO.reply(port, res.success? ? 'Request sent successfully' : "Request failed: #{res.content}")
      end
      true
    end

  end

end