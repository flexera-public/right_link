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

BASE_DIR = File.join(File.dirname(__FILE__), '..', '..', '..', '..')

require File.normalize_path(File.join(BASE_DIR, 'chef', 'lib', 'providers'))
require File.normalize_path(File.join(BASE_DIR, 'chef', 'lib', 'plugins'))
require File.normalize_path(File.join(BASE_DIR, 'common', 'lib', 'common'))
require File.normalize_path(File.join(BASE_DIR, 'command_protocol', 'lib', 'command_protocol'))
require File.normalize_path(File.join(BASE_DIR, 'payload_types', 'lib', 'payload_types'))
require File.normalize_path(File.join(BASE_DIR, 'scripts', 'lib', 'agent_utils'))

module RightScale

  class Cook

    include Utils

    # Name of agent running the cook process
    AGENT_NAME = 'instance'

    # Run bundle given in stdin
    def run

      # 1. Retrieve bundle
      input = gets.chomp
      bundle = nil
      fail('Missing bundle', 'No bundle to run') if input.blank?
      bundle = load(input, 'Invalid bundle', :json)

      # 2. Load configuration settings
      options = OptionsBag.load
      fail('Missing command server listen port') unless options[:listen_port]
      fail('Missing command cookie') unless options[:cookie]
      @client = CommandClient.new(options[:listen_port], options[:cookie])

      # 3. Run bundle
      @@instance = self
      success = nil
      agent_id  = options[:identity]
      RightLinkLog.program_name = 'RightLink'
      RightLinkLog.log_to_file_only(options[:log_to_file_only])
      RightLinkLog.init(agent_id, options[:log_path])
      sequence = ExecutableSequence.new(bundle)
      EM.threadpool_size = 1
      EM.error_handler do |e|
        RightLinkLog.error("Chef process failed with #{e.message} from:\n\t#{e.backtrace.join("\n\t")}")
        fail('Exception raised during Chef execution', "The following exception was raised during the execution of the Chef process:\n  #{e.message}")
      end
      EM.run do
        begin
          AuditStub.instance.init(options)
          sequence.callback { success = true; send_inputs_patch(sequence) }
          sequence.errback { success = false; report_failure(sequence) }
          EM.defer { sequence.run }
        rescue Exception => e
          fail('Execution failed', "Execution failed (#{e.message}) from\n#{e.backtrace.join("\n")}")
        end
      end
      exit(1) unless success
    end

    # Helper method to send a request to one or more targets with no response expected
    # See InstanceCommands for details
    def send_push(type, payload = nil, target = nil, opts = {})
      cmd = {:name => :send_push, :type => type, :payload => payload, :target => target, :options => opts}
      @client.send_command(cmd)
    end

    # Helper method to send a request to one or more targets with no response expected
    # The request is persisted en route to reduce the chance of it being lost
    # See InstanceCommands for details
    def send_persistent_push(type, payload = nil, target = nil, opts = {})
      cmd = {:name => :send_persistent_push, :type => type, :payload => payload, :target => target, :options => opts}
      @client.send_command(cmd)
    end

    # Helper method to send a request to a single target with a response expected
    # The request is retried if the response is not received in a reasonable amount of time
    # See InstanceCommands for details
    def send_retryable_request(type, payload = nil, target = nil, opts = {}, &blk)
      cmd = {:name => :send_retryable_request, :type => type, :payload => payload, :target => target, :options => opts}
      @client.send_command(cmd) do |r|
        response = load(r, "Request response #{r.inspect}")
        blk.call(response)
      end
    end

    # Helper method to send a request to a single target with a response expected
    # The request is persisted en route to reduce the chance of it being lost
    # The request is never retried if there is the possibility of it being duplicated
    # See InstanceCommands for details
    def send_persistent_request(type, payload = nil, target = nil, opts = {}, &blk)
      cmd = {:name => :send_retryable_request, :type => type, :payload => payload, :target => target, :options => opts}
      @client.send_command(cmd) do |r|
        response = load_json(r, "Request response #{r.inspect}")
        blk.call(response)
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
      @client.send_command(cmd)
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
      @client.send_command(cmd)
    end

    # Queries shutdown request state (from parent process) only if not cached
    # locally.
    #
    # === Returns
    # result(token):: current state
    def shutdown_request
      return @shutdown_request if @shutdown_request
      cmd = {:name => :get_shutdown_request}
      @client.send_command(cmd) do |result|
        if result[:error]
          RightLinkLog.error("Failed getting state of requested shutdown: #{result[:error]}")
        else
          @shutdown_request ||= ::RightScale::ShutdownManagement::ShutdownRequest.new
          @shutdown_request.level = result[:level]
          @shutdown_request.immediately! if result[:immediately]
        end
      end
      return @shutdown_request
    end

    # Updates shutdown request state (for parent process) which may be
    # superceded by a previous, higher-priority shutdown level.
    #
    # === Parameters
    # level(String):: shutdown request level
    # immediately(Boolean):: shutdown request immediacy
    #
    # === Returns
    # result(token):: current state
    def schedule_shutdown(level, immediately = false)
      cmd = {:name => :set_shutdown_request, :level => level, :immediately => !!immediately}
      @client.send_command(cmd) do |result|
        if result[:error]
          RightLinkLog.error("Failed setting state of requested shutdown: #{result[:error]}")
        else
          @shutdown_request ||= ::RightScale::ShutdownManagement::ShutdownRequest.new
          @shutdown_request.level = result[:level]
          @shutdown_request.immediately! if result[:immediately]
        end
      end
      return @shutdown_request
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
      @shutdown_request = nil
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
      begin
        cmd = { :name => :set_inputs_patch, :patch => sequence.inputs_patch }
        @client.send_command(cmd)
      rescue Exception => e
        fail('Failed to update inputs', "Failed to apply inputs patch after execution (#{e.message}) from\n#{e.backtrace.join("\n")}")
      ensure
        stop
      end
      true
    end

    # Report failure to core
    def report_failure(sequence)
      begin
        AuditStub.instance.append_error(sequence.failure_title, :category => RightScale::EventCategories::CATEGORY_ERROR) if sequence.failure_title
        AuditStub.instance.append_error(sequence.failure_message) if sequence.failure_message
      rescue Exception => e
        fail('Failed to report failure', "Failed to report failure after execution (#{e.message}) from\n#{e.backtrace.join("\n")}")
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
          RightLinkLog.info('[cook] Failed to stop command client cleanly, forcing shutdown...') if timeout
          EM.stop
        end
      end
    end

  end
end
