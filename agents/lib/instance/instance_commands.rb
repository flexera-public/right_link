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
      :list                     => 'List all available commands with their description',
      :run_recipe               => 'Run recipe with id given in options[:id] and optionally JSON given in options[:json]',
      :run_right_script         => 'Run RightScript with id given in options[:id] and arguments given in hash options[:arguments] (e.g. { \'application\' => \'text:Mephisto\' })',
      :send_push                => 'Send request to one or more remote agents with no response expected',
      :send_persistent_push     => 'Send request to one or more remote agents with no response expected with persistence en route',
      :send_retryable_request   => 'Send request to a remote agent with a response expected and retry if response times out',
      :send_persistent_request  => 'Send request to a remote agent with a response expected with persistence ' +
                                   'en route and no retries that would result in it being duplicated',
      :send_idempotent_request  => 'Send a request to a remote agent (identified solely by operation), retrying at the' +
                                   'application level until the request succeeds or the timeout elapses',
      :set_log_level            => 'Set log level to options[:level]',
      :get_log_level            => 'Get log level',
      :decommission             => 'Run instance decommission bundle synchronously',
      :terminate                => 'Terminate agent',
      :get_tags                 => 'Retrieve instance tags',
      :add_tag                  => 'Add given tag',
      :remove_tag               => 'Remove given tag',
      :query_tags               => 'Query for instances with specified tags',
      :audit_update_status      => 'Update last audit title',
      :audit_create_new_section => 'Create new audit section',
      :audit_append_output      => 'Append process output to audit',
      :audit_append_info        => 'Append info message to audit',
      :audit_append_error       => 'Append error message to audit',
      :set_inputs_patch         => 'Set inputs patch post execution',
      :check_connectivity       => 'Check whether the instance is able to communicate',
      :close_connection         => 'Close persistent connection (used for auditing)',
      :stats                    => 'Get statistics about instance agent operation',
      :get_shutdown_request     => 'Gets the requested reboot state.',
      :set_shutdown_request     => 'Sets the requested reboot state.'
    }

    # Build hash of commands associating command names with block
    #
    # === Parameters
    # agent_identity(String):: Serialized instance agent identity
    # scheduler(InstanceScheduler):: Scheduler used by decommission command
    # agent_manager(AgentManager):: Agent manager used by stats command
    #
    # === Return
    # cmds(Hash):: Hash of command blocks keyed by command names
    def self.get(agent_identity, scheduler, agent_manager)
      cmds = {}
      target = new(agent_identity, scheduler, agent_manager)
      COMMANDS.each { |k, _| cmds[k] = lambda { |opts, conn| opts[:conn] = conn; target.send("#{k.to_s}_command", opts) } }
      cmds
    end

    # Set token id used to send core requests
    #
    # === Parameter
    # agent_identity(String):: Serialized instance agent identity
    # scheduler(InstanceScheduler):: Scheduler used by decommission command
    # agent_manager(AgentManager):: Agent manager used by stats command
    def initialize(agent_identity, scheduler, agent_manager)
      @agent_identity = agent_identity
      @scheduler = scheduler
      @serializer = Serializer.new
      @agent_manager = agent_manager
    end

    protected

    # List command implementation
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
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
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:options](Hash):: Pass-through options sent to forwarder or instance_scheduler
    #   with a :tags value indicating tag-based routing instead of local execution
    #
    # === Return
    # true:: Always return true
    def run_recipe_command(opts)
      payload = opts[:options] || {}
      target = {}
      target[:tags] = payload.delete(:tags) if payload[:tags]
      target[:scope] = payload.delete(:scope) if payload[:scope]
      target[:selector] = payload.delete(:selector) if payload[:selector]
      if (target[:tags] && !target[:tags].empty?) || target[:scope] || (target[:selector] && target(:selector) == :all)
        send_persistent_push("/instance_scheduler/execute", opts[:conn], payload, target)
      else
        send_persistent_request("/forwarder/schedule_recipe", opts[:conn], payload)
      end
    end

    # Run RightScript command implementation
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:options](Hash):: Pass-through options sent to forwarder or instance_scheduler
    #   with a :tags value indicating tag-based routing instead of local execution
    #
    # === Return
    # true:: Always return true
    def run_right_script_command(opts)
      payload = opts[:options] || {}
      target = {}
      target[:tags] = payload.delete(:tags) if payload[:tags]
      target[:scope] = payload.delete(:scope) if payload[:scope]
      target[:selector] = payload.delete(:selector) if payload[:selector]
      if (target[:tags] && !target[:tags].empty?) || target[:scope] || (target[:selector] && target(:selector) == :all)
        send_persistent_push("/instance_scheduler/execute", opts[:conn], payload, target)
      else
        send_persistent_request("/forwarder/schedule_right_script", opts[:conn], payload)
      end
    end

    # Send a request to one or more targets with no response expected
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:type](String):: Request type
    # opts[:payload](String):: Request data, optional
    # opts[:target](String|Hash):: Request target or target selectors, optional
    # opts[:options](Hash):: Request options
    #
    # === Return
    # true:: Always return true
    def send_push_command(opts)
      send_push(opts[:type], opts[:conn], opts[:payload], opts[:target], opts[:options])
    end

    # Send a request to one or more targets with no response expected
    # Persist the request en route to reduce the chance of it being lost at the expense of some
    # additional network overhead
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:type](String):: Request type
    # opts[:payload](String):: Request data, optional
    # opts[:target](String|Hash):: Request target or target selectors, optional
    # opts[:options](Hash):: Request options
    #
    # === Return
    # true:: Always return true
    def send_persistent_push_command(opts)
      send_persistent_push(opts[:type], opts[:conn], opts[:payload], opts[:target], opts[:options])
    end

    # Send a request to a single target with a response expected
    # Automatically retry the request if the response is not received in a reasonable amount of time
    # Timeout the request if a response is not received in time, typically configured to 2 minutes
    # Allow the request to expire per the agent's configured time-to-live, typically 1 minute
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:type](String):: Request type
    # opts[:payload](String):: Request data, optional
    # opts[:target](String|Hash):: Request target or target selectors (random pick if multiple), optional
    # opts[:options](Hash):: Request options
    #
    # === Return
    # true:: Always return true
    def send_retryable_request_command(opts)
      send_retryable_request(opts[:type], opts[:conn], opts[:payload], opts[:target], opts[:options])
    end

    # Send a request to a single target with a response expected
    # Persist the request en route to reduce the chance of it being lost at the expense of some
    # additional network overhead
    # Never retry the request if there is the possibility of it being duplicated
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:type](String):: Request type
    # opts[:payload](String):: Request data, optional
    # opts[:target](String|Hash):: Request target or target selectors (random pick if multiple), optional
    # opts[:options](Hash):: Request options
    #
    # === Return
    # true:: Always return true
    def send_persistent_request_command(opts)
      send_persistent_request(opts[:type], opts[:conn], opts[:payload], opts[:target], opts[:options])
    end

    # Send a retryable request to a single target with a response expected, retrying multiple times
    # at the application layer in case failures or errors occur.
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:type](String):: Request type
    # opts[:payload](String):: Request data, optional
    # opts[:timeout](Integer):: Timeout for idempotent request, -1 or nil for no timeout
    # opts[:options](Hash):: Request options
    #
    # === Return
    # true:: Always return true
    def send_idempotent_request_command(opts)
      send_idempotent_request(opts[:type], opts[:conn], opts[:payload], opts[:options])
    end

    # Set log level command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:level](Symbol):: One of :debug, :info, :warn, :error or :fatal
    #
    # === Return
    # true:: Always return true
    def set_log_level_command(opts)
      RightLinkLog.level = opts[:level] if [ :debug, :info, :warn, :error, :fatal ].include?(opts[:level])
      CommandIO.instance.reply(opts[:conn], RightLinkLog.level)
    end

    # Get log level command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    #
    # === Return
    # true:: Always return true
    def get_log_level_command(opts)
      CommandIO.instance.reply(opts[:conn], RightLinkLog.level)
    end

    # Decommission command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    #
    # === Return
    # true:: Always return true
    def decommission_command(opts)
      @scheduler.run_decommission { CommandIO.instance.reply(opts[:conn], 'Decommissioned') }
    end

    # Terminate command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    #
    # === Return
    # true:: Always return true
    def terminate_command(opts)
      CommandIO.instance.reply(opts[:conn], 'Terminating')
      @scheduler.terminate
    end

    # Get tags command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    #
    # === Return
    # true:: Always return true
    def get_tags_command(opts)
      AgentTagsManager.instance.tags { |t| CommandIO.instance.reply(opts[:conn], t) }
    end

    # Add given tag
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:tag](String):: Tag to be added
    #
    # === Return
    # true:: Always return true
    def add_tag_command(opts)
      AgentTagsManager.instance.add_tags(opts[:tag])
      CommandIO.instance.reply(opts[:conn], "Request to add tag '#{opts[:tag]}' sent successfully.")
    end

    # Remove given tag
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:tag](String):: Tag to be removed
    #
    # === Return
    # true:: Always return true
    def remove_tag_command(opts)
      AgentTagsManager.instance.remove_tags(opts[:tag])
      CommandIO.instance.reply(opts[:conn], "Request to remove tag '#{opts[:tag]}' sent successfully.")
    end

    # Query for instances with given tags
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:tags](String):: Tags to be used in query
    #
    # === Return
    # true:: Always return true
    def query_tags_command(opts)
      send_persistent_request('/mapper/query_tags', opts[:conn], :tags => opts[:tags])
    end

    # Update audit summary
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:title](Hash):: Chef attributes hash
    #
    # === Return
    # true:: Always return true
    def audit_update_status_command(opts)
      AuditCookStub.instance.forward_audit(:update_status, opts[:content], opts[:options])
      CommandIO.instance.reply(opts[:conn], 'OK', close_after_writing=false)
    end

    # Update audit summary
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:title](Hash):: Chef attributes hash
    #
    # === Return
    # true:: Always return true
    def audit_create_new_section_command(opts)
      AuditCookStub.instance.forward_audit(:create_new_section, opts[:content], opts[:options])
      CommandIO.instance.reply(opts[:conn], 'OK', close_after_writing=false)
    end

    # Update audit summary
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:title](Hash):: Chef attributes hash
    #
    # === Return
    # true:: Always return true
    def audit_append_output_command(opts)
      AuditCookStub.instance.forward_audit(:append_output, opts[:content], opts[:options])
      CommandIO.instance.reply(opts[:conn], 'OK', close_after_writing=false)
    end

    # Update audit summary
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:title](Hash):: Chef attributes hash
    #
    # === Return
    # true:: Always return true
    def audit_append_info_command(opts)
      AuditCookStub.instance.forward_audit(:append_info, opts[:content], opts[:options])
      CommandIO.instance.reply(opts[:conn], 'OK', close_after_writing=false)
    end

    # Update audit summary
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:title](Hash):: Chef attributes hash
    #
    # === Return
    # true:: Always return true
    def audit_append_error_command(opts)
      AuditCookStub.instance.forward_audit(:append_error, opts[:content], opts[:options])
      CommandIO.instance.reply(opts[:conn], 'OK', close_after_writing=false)
    end

    # Update inputs patch to be sent back to core after cook process finishes
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:patch](Hash):: Patch to be forwarded to core
    #
    # === Return
    # true:: Always return true
    def set_inputs_patch_command(opts)
      payload = {:agent_identity => @agent_identity, :patch => opts[:patch]}
      send_persistent_push("/updater/update_inputs", opts[:conn], payload, nil, opts)
      CommandIO.instance.reply(opts[:conn], 'OK')
    end

    # Check whether this instance agent is connected by pinging a mapper
    #
    # === Return
    # true:: Always return true
    def check_connectivity_command(opts)
      send_persistent_request("/mapper/ping", opts[:conn], nil, nil, opts)
      true
    end

    # Close connection
    def close_connection_command(opts)
      AuditCookStub.instance.close
      CommandIO.instance.reply(opts[:conn], 'OK')
    end

    # Helper method to send a request to one or more targets with no response expected
    # See MapperProxy for details
    def send_push(type, conn, payload = nil, target = nil, opts = {})
      payload ||= {}
      payload[:agent_identity] = @agent_identity
      MapperProxy.instance.send_push(type, payload, target, opts.merge(:offline_queueing => true))
      CommandIO.instance.reply(conn, 'OK')
      true
    end

    # Helper method to send a request to one or more targets with no response expected
    # The request is persisted en route to reduce the chance of it being lost at the expense of some
    # additional network overhead
    # See MapperProxy for details
    def send_persistent_push(type, conn, payload = nil, target = nil, opts = {})
      payload ||= {}
      payload[:agent_identity] = @agent_identity
      MapperProxy.instance.send_persistent_push(type, payload, target, opts.merge(:offline_queueing => true))
      CommandIO.instance.reply(conn, 'OK')
      true
    end

    # Helper method to send a request to a single target with a response expected
    # The request is retried if the response is not received in a reasonable amount of time
    # The request is timed out if not received in time, typically configured to 2 minutes
    # The request is allowed to expire per the agent's configured time-to-live, typically 1 minute
    # See MapperProxy for details
    def send_retryable_request(type, conn, payload = nil, target = nil, opts = {})
      payload ||= {}
      payload[:agent_identity] = @agent_identity
      MapperProxy.instance.send_retryable_request(type, payload, target, opts.merge(:offline_queueing => true)) do |r|
        reply = @serializer.dump(r) rescue '\"Failed to serialize response\"'
        CommandIO.instance.reply(conn, reply)
      end
      true
    end

    # Helper method to send a request to a single target with a response expected
    # The request is persisted en route to reduce the chance of it being lost at the expense of some
    # additional network overhead
    # The request is never retried if there is the possibility of it being duplicated
    # See MapperProxy for details
    def send_persistent_request(type, conn, payload = nil, target = nil, opts = {})
      payload ||= {}
      payload[:agent_identity] = @agent_identity
      MapperProxy.instance.send_persistent_request(type, payload, target, opts.merge(:offline_queueing => true)) do |r|
        reply = @serializer.dump(r) rescue '\"Failed to serialize response\"'
        CommandIO.instance.reply(conn, reply)
      end
      true
    end

    # Helper method to send a retryable (and therefore idempotent!) request to a single target with a response
    # expected, retrying at the application layer until the request succeeds or the timeout elapses; default
    # timeout is 'forever'.
    #
    # See IdempotentRequest for details
    def send_idempotent_request(type, conn, payload=nil, opts={})
      req = IdempotentRequest.new(type, payload, opts)

      callback = Proc.new do |content|
        result = OperationResult.success(content)
        reply = @serializer.dump(result) rescue '\"Failed to serialize response\"'
        CommandIO.instance.reply(conn, reply)
      end

      errback = Proc.new do |content|
        result = OperationResult.error(content)
        reply = @serializer.dump(result) rescue '\"Failed to serialize response\"'
        CommandIO.instance.reply(conn, reply)
      end

      req.callback(&callback)
      req.errback(&errback)
      req.run
    end

    # Stats command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:reset](Boolean):: Whether to reset stats
    #
    # === Return
    # true:: Always return true
    def stats_command(opts)
      CommandIO.instance.reply(opts[:conn], JSON.dump(@agent_manager.stats({:reset => opts[:reset]})))
    end

    # Get shutdown request command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    #
    # === Return
    # true:: Always return true
    def get_shutdown_request_command(opts)
      shutdown_request = ShutdownRequest.instance
      CommandIO.instance.reply(opts[:conn], { :level => shutdown_request.level, :immediately => shutdown_request.immediately? })
    rescue Exception => e
      CommandIO.instance.reply(opts[:conn], { :error => e.message })
    end

    # Set reboot timeout command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    # opts[:level](String):: shutdown request level
    # opts[:immediately](Boolean):: shutdown immediacy or nil
    #
    # === Return
    # true:: Always return true
    def set_shutdown_request_command(opts)
      shutdown_request = ShutdownRequest.submit(opts)
      CommandIO.instance.reply(opts[:conn], { :level => shutdown_request.level, :immediately => shutdown_request.immediately? })
    rescue Exception => e
      CommandIO.instance.reply(opts[:conn], { :error => e.message })
    end

  end # InstanceCommands

end # RightScale
