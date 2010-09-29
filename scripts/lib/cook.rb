# === Synopsis:
#   RightScale Chef Cook - (c) 2010 RightScale
#
#   This utility is meant to be used internally by RightLink, use
#   rs_run_right_script and rs_run_recipe instead.
#

require 'rubygems'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require 'eventmachine'
require 'chef'
require 'fileutils'
require 'right_scraper'

BASE_DIR = File.join(File.dirname(__FILE__), '..', '..')

require File.normalize_path(File.join(BASE_DIR, 'agents', 'lib', 'instance'))
require File.normalize_path(File.join(BASE_DIR, 'agents', 'lib', 'instance', 'cook'))
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
      json = gets.chomp
      bundle = nil
      fail('Missing bundle', 'No bundle to run') if json.blank?
      bundle = load_json(json, 'Invalid bundle')

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
      InstanceState.init(agent_id)
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

    # Send request using command server
    #
    # === Parameters
    # type(String):: Request service (e.g. '/booter/declare')
    # payload(String):: Associated payload, optional
    # opts(Hash):: Options as allowed by Request packet, optional
    #
    # === Block
    # Handler block gets called back with request results
    #
    # === Return
    # true:: Always return true
    def request(type, payload = '', opts = {}, &blk)
      cmd = { :name => :send_request, :type => type, :payload => payload, :options => opts }
      @client.send_command(cmd) do |r|
        response = load_json(r, "Request response #{r.inspect}")
        blk.call(response)
      end
    end

    # Send push using command server
    #
    # === Parameters
    # type(String):: Request service (e.g. '/booter/declare')
    # payload(String):: Associated payload, optional
    # opts(Hash):: Options as allowed by Request packet, optional
    #
    # === Return
    # true:: Always return true
    def push(type, payload = '', opts = {})
      cmd = { :name => :send_push, :type => type, :payload => payload, :options => opts }
      @client.send_command(cmd)
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

    # Load JSON content
    # fail if JSON is invalid
    #
    # === Parameters
    # json(String):: Serialized JSON
    # error_message(String):: Error to be logged/audited in case of failure
    #
    # === Return
    # content(String):: Deserialized content
    def load_json(json, error_message)
      content = nil
      begin
        content = JSON.load(json)
      rescue Exception => e
        fail(error_message, "Failed to load JSON (#{e.message}):\n#{json.inspect}")
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
          if timeout
            RightLinkLog.info('[cook] Failed to stop command client cleanly, forcing shutdown...')
          else
            RightLinkLog.info("[cook] Disconnected from agent")
          end
          EM.stop
        end
      end
    end

  end
end

# Launch it!
RightScale::Cook.new.run

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

