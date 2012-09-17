#
# Copyright (c) 2010-2012 RightScale Inc
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

require 'right_agent'
require 'right_agent/core_payload_types'


require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'chef', 'right_providers'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'chef', 'plugins'))

module RightScale

  class Cook

    # Name of agent running the cook process
    AGENT_NAME = 'instance'

    # Exceptions
    class TagError < Exception; end
    class BlockingError < Exception; end

    # Run bundle given in stdin
    def run
      AgentConfig.root_dir = AgentConfig.right_link_root_dirs

      # 1. Load configuration settings
      options = OptionsBag.load
      agent_id  = options[:identity]

      Log.program_name = 'RightLink'
      Log.facility = 'user'
      Log.log_to_file_only(options[:log_to_file_only])
      Log.init(agent_id, options[:log_path])
      Log.level = CookState.log_level
      # add an additional logger if the agent is set to log to an alternate 
      # location (install, operate, decommission, ...)
      Log.add_logger(::Logger.new(CookState.log_file)) if CookState.log_file

      Log.info("[cook] Process starting up with dev tags: [#{CookState.startup_tags.select { |tag| tag.include?(CookState::DEV_TAG_NAMESPACE)}.join(', ')}]")
      fail('Missing command server listen port') unless options[:listen_port]
      fail('Missing command cookie') unless options[:cookie]
      @client = CommandClient.new(options[:listen_port], options[:cookie])
      ShutdownRequestProxy.init(@client)

      # 2. Retrieve bundle
      input = gets.chomp
      begin
        bundle = RightScale::MessageEncoder.for_agent(agent_id).decode(input)
      rescue Exception => e
        fail('Invalid bundle', e.message)
      end

      fail('Missing bundle', 'No bundle to run') if bundle.nil?

      @thread_name = bundle.runlist_policy.thread_name if bundle.respond_to?(:runlist_policy) && bundle.runlist_policy
      @thread_name ||= RightScale::AgentConfig.default_thread_name
      options[:thread_name] = @thread_name

      # Chef state needs the server secret so it can encrypt state on disk.
      # The secret is the same for all instances of the server (i.e. is still
      # valid after stop and restart server).
      server_secret = bundle.server_secret || AgentConfig.default_server_secret
      ChefState.init(agent_id, server_secret, reset=false)

      # 3. Run bundle
      @@instance = self
      success = nil
      Log.debug("[cook] Thread name associated with bundle = #{@thread_name}")
      gatherer = ExternalParameterGatherer.new(bundle, options)
      sequence = ExecutableSequence.new(bundle)
      EM.threadpool_size = 1
      EM.error_handler do |e|
        Log.error("Execution failed", e, :trace)
        fail('Exception caught', "The following exception was caught during execution:\n  #{e.message}")
      end
      EM.run do
        begin
          AuditStub.instance.init(options)
          gatherer.callback { EM.defer { sequence.run } }
          gatherer.errback { success = false; report_failure(gatherer) }
          sequence.callback { success = true; send_inputs_patch(sequence) }
          sequence.errback { success = false; report_failure(sequence) }

          EM.defer { gatherer.run }
        rescue Exception => e
          fail('Execution failed', Log.format("Execution failed", e, :trace))
        end
      end

    rescue Exception => e
      fail('Execution failed', Log.format("Run failed", e, :trace))

    ensure
      Log.info("[cook] Process stopping")
      exit(1) unless success
    end

    # Determines if the current cook process has the default thread for purposes
    # of concurrency with non-defaulted cooks.
    def has_default_thread?
      ::RightScale::AgentConfig.default_thread_name == @thread_name
    end

    # Helper method to send a request to one or more targets with no response expected
    # See InstanceCommands for details
    def send_push(type, payload = nil, target = nil, opts = {})
      cmd = {:name => :send_push, :type => type, :payload => payload, :target => target, :options => opts}
      # Need to execute on EM main thread where command client is running
      EM.next_tick { @client.send_command(cmd) }
    end

    # Add given tag to tags exposed by corresponding server
    #
    # === Parameters
    # tag(String):: Tag to be added
    #
    # === Return
    # result(Hash):: contents of response
    def query_tags(tags, agent_ids=nil, timeout=120)
      cmd = { :name => :query_tags, :tags => tags }
      cmd[:agent_ids] = agent_ids unless agent_ids.nil? || agent_ids.empty?
      response = blocking_request(cmd, timeout)
      begin
        result = OperationResult.from_results(load(response, "Unexpected response #{response.inspect}"))
        raise TagError.new("Query tags failed: #{result.content}") unless result.success?
        return result.content
      rescue
        raise TagError.new("Query tags failed: #{response.inspect}")
      end
    end

    # Add given tag to tags exposed by corresponding server
    #
    # === Parameters
    # tag(String):: Tag to be added
    # timeout(Fixnum):: Number of seconds to wait for agent response
    #
    # === Return
    # true:: Always return true
    def add_tag(tag_name, timeout)
      cmd = { :name => :add_tag, :tag => tag_name }
      response = blocking_request(cmd, timeout)
      result = OperationResult.from_results(load(response, "Unexpected response #{response.inspect}"))
      if result.success?
        ::Chef::Log.info("Successfully added tag #{tag_name}")
      else
        raise TagError.new("Add tag failed: #{result.content}")
      end
      true
    end

    # Remove given tag from tags exposed by corresponding server
    #
    # === Parameters
    # tag(String):: Tag to be removed
    # timeout(Fixnum):: Number of seconds to wait for agent response
    #
    # === Return
    # true:: Always return true
    def remove_tag(tag_name, timeout)
      cmd = { :name => :remove_tag, :tag => tag_name }
      response = blocking_request(cmd, timeout)
      result = OperationResult.from_results(load(response, "Unexpected response #{response.inspect}"))
      if result.success?
        ::Chef::Log.info("Successfully removed tag #{tag_name}")
      else
        raise TagError.new("Remove tag failed: #{result.content}")
      end
      true
    end

    # Retrieve current instance tags
    #
    # === Parameters
    # timeout(Fixnum):: Number of seconds to wait for agent response
    def load_tags(timeout)
      cmd = { :name => :get_tags }
      response = blocking_request(cmd, timeout)
      result = OperationResult.from_results(load(response, "Unexpected response #{response.inspect}"))
      res = result.content
      if result.success?
        ::Chef::Log.info("Successfully loaded current tags: '#{res.join("', '")}'")
      else
        raise TagError.new("Retrieving current tags failed: #{res}")
      end
      res
    end

    # Access cook instance from anywhere to send requests to core through
    # command protocol
    def self.instance
      @@instance
    end

    protected

    # Initialize instance variables
    def initialize
      @client = nil
    end

    # Report inputs patch to core
    def send_inputs_patch(sequence)
      if has_default_thread?
        begin
          cmd = { :name => :set_inputs_patch, :patch => sequence.inputs_patch }
          @client.send_command(cmd)
        rescue Exception => e
          fail('Failed to update inputs', Log.format("Failed to apply inputs patch after execution", e, :trace))
        end
      end
      true
    ensure
      stop
    end

    # Report failure to core
    def report_failure(subject)
      begin
        AuditStub.instance.append_error(subject.failure_title, :category => RightScale::EventCategories::CATEGORY_ERROR) if subject.failure_title
        AuditStub.instance.append_error(subject.failure_message) if subject.failure_message
      rescue Exception => e
        fail('Failed to report failure', Log.format("Failed to report failure after execution", e, :trace))
      ensure
        stop
      end
    end

    # Print failure message and exit abnormally
    def fail(title, message=nil)
      $stderr.puts title
      $stderr.puts message || title
      if @client
        @client.stop { AuditStub.instance.stop { exit(1) } }
      else
        exit(1)
      end
    end

    # Stop command client then stop auditor stub then EM
    def stop
      AuditStub.instance.stop do
        @client.stop do |timeout|
          Log.info('[cook] Failed to stop command client cleanly, forcing shutdown...') if timeout
          EM.stop
        end
      end
    end

    # Provides a blocking request for the given command
    # Can only be called when on EM defer thread
    #
    # === Parameters
    # cmd(Hash):: request to send
    #
    # === Return
    # response(String):: raw response
    #
    # === Raise
    # BlockingError:: If request called when on EM main thread
    def blocking_request(cmd, timeout)
      raise BlockingError, "Blocking request not allowed on EM main thread for command #{cmd.inspect}" if EM.reactor_thread?
      # Use a queue to block and wait for response
      response_queue = Queue.new
      # Need to execute on EM main thread where command client is running
      EM.next_tick { @client.send_command(cmd, false, timeout) { |response| response_queue << response } }
      return response_queue.shift
    end

    # Load serialized content
    # fail if serialized data is invalid
    #
    # === Parameters
    # data(String):: Serialized content
    # error_message(String):: Error to be logged/audited in case of failure
    # format(Symbol):: Serialization format
    #
    # === Return
    # content(String):: Unserialized content
    def load(data, error_message, format = nil)
      serializer = Serializer.new(format)
      content = nil
      begin
        content = serializer.load(data)
      rescue Exception => e
        fail(error_message, "Failed to load #{serializer.format.to_s} data (#{e}):\n#{data.inspect}")
      end
      content
    end

  end
end
