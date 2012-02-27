#
# Copyright (c) 2010-11 RightScale Inc
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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'chef', 'providers'))
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

      # 1. Retrieve bundle
      input = gets.chomp
      bundle = nil
      fail('Missing bundle', 'No bundle to run') if input.blank?
      bundle = load(input, 'Invalid bundle', :json)
      @thread_name = bundle.thread_name

      # 2. Load configuration settings
      options = OptionsBag.load
      fail('Missing command server listen port') unless options[:listen_port]
      fail('Missing command cookie') unless options[:cookie]
      options[:thread_name] = @thread_name
      @client = CommandClient.new(options[:listen_port], options[:cookie])
      ShutdownRequestProxy.init(@client)

      # 3. Run bundle
      @@instance = self
      success = nil
      agent_id  = options[:identity]
      Log.program_name = 'RightLink'
      Log.log_to_file_only(options[:log_to_file_only])
      Log.init(agent_id, options[:log_path])
      Log.level = CookState.log_level
      Log.debug("[cook] Thread name associated with bundle = #{@thread_name}")
      gatherer = ExternalParameterGatherer.new(bundle, options)
      sequence = ExecutableSequence.new(bundle)
      EM.threadpool_size = 1
      EM.error_handler do |e|
        Log.error("Chef process failed", e, :trace)
        fail('Exception raised during Chef execution', "The following exception was raised during the execution of the Chef process:\n  #{e.message}")
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
    def query_tags(tags, agent_ids = nil)
      cmd = { :name => :query_tags, :tags => tags }
      cmd[:agent_ids] = agent_ids unless agent_ids.nil? || agent_ids.empty?
      response = blocking_request(cmd)
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
    #
    # === Return
    # true:: Always return true
    def add_tag(tag_name)
      cmd = { :name => :add_tag, :tag => tag_name }
      response = blocking_request(cmd)
      begin
        result = OperationResult.from_results(load(response, "Unexpected response #{response.inspect}"))
        if result.success?
          ::Chef::Log.info("Successfully added tag #{tag_name}")
        else
          raise TagError.new("Add tag failed: #{result.content}")
        end
      rescue
        raise TagError.new("Add tag failed: #{response.inspect}")
      end
      true
    end

    # Remove given tag from tags exposed by corresponding server
    #
    # === Parameters
    # tag(String):: Tag to be removed
    #
    # === Return
    # true:: Always return true
    def remove_tag(tag_name)
      cmd = { :name => :remove_tag, :tag => tag_name }
      response = blocking_request(cmd)
      begin
        result = OperationResult.from_results(load(response, "Unexpected response #{response.inspect}"))
        if result.success?
          ::Chef::Log.info("Successfully removed tag #{tag_name}")
        else
          raise TagError.new("Remove tag failed: #{result.content}")
        end
      rescue
        raise TagError.new("Remove tag failed: #{response.inspect}")
      end
      true
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
    def blocking_request(cmd)
      raise BlockingError, "Blocking request not allowed on EM main thread for command #{cmd.inspect}" if EM.reactor_thread?
      # Use a queue to block and wait for response
      response_queue = Queue.new
      # Need to execute on EM main thread where command client is running
      EM.next_tick { @client.send_command(cmd) { |response| response_queue << response } }
      return response_queue.shift
    end

  end
end
