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

ENV['RS_RUBY_EXE'] = ENV['RS_RUBY_EXE'] || `which ruby`.chomp

require 'rubygems'

# Mappers and agents use the JSON gem, which -- if used in a project that also uses ActiveRecord --
# MUST be loaded after ActiveRecord in order to ensure that a monkey patch is correctly applied
# We tentatively try to load AR here in case RightLink specs are ever executed in a context where
# ActiveRecord is also loaded
begin
  require 'active_support'

  # Monkey-patch the JSON gem's load/dump interface to avoid
  # the clash between ActiveRecord's Hash#to_json and
  # the gem's Hash#to_json.
  module JSON
    class <<self
      def dump(obj)
        obj.to_json
      end
    end
  end

rescue LoadError => e
  # Make sure we're dealing with a legitimate missing-file LoadError
  raise e unless e.message =~ /^no such file to load/
end

# The daemonize method of AR clashes with the daemonize Chef attribute, we don't need that method so undef it
undef :daemonize if methods.include?('daemonize')

require 'flexmock'
require 'spec'
require 'eventmachine'
require 'fileutils'
require 'right_agent'
require 'right_agent/core_payload_types'
require 'stringio'

# monkey-patch EM for to ensure EM.stop is only called via proper channels in
# EmTestRunner (see below). if EM is used outside of EmTestRunner then this
# check has no effect.
module EventMachine
  @old_em_stop = self.method :stop
  def self.stop
    RightScale::SpecHelper::EmTestRunner.assert_em_test_not_running
    @old_em_stop.call
  end
end

# HACK: disable garbage collector (in Windows only?) for spec run as flexmocked
# types cause segmentation faults when flexmocked objects are gc'd on a thread
# other than where they were defined and allocated.
begin
  GC.disable if ::RightScale::Platform.windows?
rescue Exception => e
  puts "#{e.class}: #{e.message}", e.backtrace.join("\n")
end

require File.join(File.dirname(__FILE__), 'results_mock')

config = Spec::Runner.configuration
config.mock_with :flexmock

RightScale::Log.init

$TESTING = true
$VERBOSE = nil # Disable constant redefined warning
TEST_SOCKET_PORT = 80000

module RightScale

  module SpecHelper

    RIGHT_LINK_SPEC_HELPER_TEMP_PATH = File.normalize_path(File.join(RightScale::Platform.filesystem.temp_dir, 'right_link_spec_helper'))

    # Setup instance state for tests
    # Use different identity to reset list of past scripts
    # Override mock_instance_state if do not want to mock InstanceState#record_state
    # but then must be running in EM before setup_state is called and must do own
    # InstanceState.init
    def setup_state(identity = '1', mock_instance_state = true)
      cleanup_state
      flexmock(RightScale::AgentTagManager.instance).should_receive(:tags).and_yield(['foo'])
      InstanceState.const_set(:STATE_FILE, state_file_path)
      InstanceState.const_set(:BOOT_LOG_FILE, log_path)
      InstanceState.const_set(:OPERATION_LOG_FILE, log_path)
      InstanceState.const_set(:DECOMMISSION_LOG_FILE, log_path)
      CookState.const_set(:STATE_FILE, cook_state_file_path)
      RightScale::ChefState.const_set(:STATE_FILE, chef_file_path) if RightScale.const_defined?(:ChefState)
      RightScale::ChefState.const_set(:SCRIPTS_FILE, past_scripts_path) if RightScale.const_defined?(:ChefState)

      @identity = identity
      @results_factory = ResultsMock.new
      @sender = flexmock('Sender')
      flexmock(Sender).should_receive(:instance).and_return(@sender).by_default
      RightScale.module_eval("Sender = Sender") unless defined?(::RightScale::Sender)
      @sender.should_receive(:identity).and_return(@identity).by_default
      @sender.should_receive(:send_push).by_default
      @sender.should_receive(:send_persistent_push).by_default
      @sender.should_receive(:send_retryable_request).and_yield(@results_factory.success_results).by_default
      @sender.should_receive(:send_persistent_request).and_yield(@results_factory.success_results).by_default
      @sender.should_receive(:message_received).by_default
      flexmock(InstanceState).should_receive(:record_state).and_return(true).by_default if mock_instance_state

      InstanceState.init(@identity) if mock_instance_state
      CookState.init

      # fake the instance certs
      certificate, key = issue_cert

      flexmock(AgentConfig).should_receive(:certs_file).with("instance.cert").and_return("instance.cert")
      flexmock(AgentConfig).should_receive(:certs_file).with("instance.key").and_return("instance.key")

      flexmock(Certificate).should_receive(:load).with("instance.cert").and_return(certificate)
      flexmock(RsaKeyPair).should_receive(:load).with("instance.key").and_return(key)

      ChefState.init(@identity, secret='some secret', reset=false)

      # should yield last in case caller wants to override the defaults
      yield if block_given?
    end

    # Cleanup files generated by instance state
    def cleanup_state
      delete_if_exists(state_file_path)
      delete_if_exists(chef_file_path)
      delete_if_exists(past_scripts_path)
      delete_if_exists(log_path)
      delete_if_exists(cook_state_file_path)
    end

    # Path to serialized instance state
    def state_file_path
      File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '__state.js')
    end

    # Path to serialized instance state
    def chef_file_path
      File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '__chef.js')
    end

    # Path to saved passed scripts
    def past_scripts_path
      File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '__past_scripts.js')
    end

    # Path to cook state file
    def cook_state_file_path
      File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '__cook_state.js')
    end

    # Path to instance boot logs
    def log_path
      File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '__agent.log')
    end

    # Test and delete if exists
    def delete_if_exists(file)
      # Windows cannot delete open files, but we only have a path at this point
      # so it's too late to close the file. report failure to delete files but
      # otherwise continue without failing test.
      begin
        File.delete(file) if File.file?(file)
      rescue Exception => e
        puts "\nWARNING: #{e.message}"
      end
    end

    # Setup location of files generated by script execution
    def setup_script_execution
      Dir.glob(File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '__TestScript*')).should be_empty
      Dir.glob(File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, '[0-9]*')).should be_empty
      AgentConfig.cache_dir = File.join(RIGHT_LINK_SPEC_HELPER_TEMP_PATH, 'cache')
    end

    # Cleanup files generated by script execution
    def cleanup_script_execution
      FileUtils.rm_rf(AgentConfig.cache_dir)
    end

    # generating the first cert info takes too long (on Windows) and can cause
    # existing EM tests to timeout, so allow for generating cert once per spec
    # run and cache it.
    class CertificateInfo
      @@certificate = nil
      @@key = nil

      def self.init
        unless @@certificate && @@key
          test_dn = { 'C'  => 'US',
                      'ST' => 'California',
                      'L'  => 'Santa Barbara',
                      'O'  => 'Agent',
                      'OU' => 'Certification Services',
                      'CN' => 'Agent test' }
          dn = DistinguishedName.new(test_dn)
          @@key = RsaKeyPair.new
          @@certificate = Certificate.new(@@key, dn, dn)
        end
      end

      def self.issue_cert
        init
        [@@certificate, @@key]
      end
    end

    # Create test certificate
    def issue_cert
      CertificateInfo.issue_cert
    end

    # container for EM test state.
    class EmTestRunner

      # timeout exception
      class RunEmTestTimeout < Exception; end

      def self.run(options, &callback)
        options ||= {}
        fail "Callback is required" unless callback
        defer = options.has_key?(:defer) ? options[:defer] : true
        timeout = options[:timeout] || 5
        EM.threadpool_size = 1
        @last_exception = nil
        @em_test_block_running = false
        @em_test_stopping = false
        @em_test_stopped = false
        tester = lambda { do_test(&callback) }
        EM.run do
          @em_test_block_running = true
          EM.add_timer(timeout) do
            begin
              raise RunEmTestTimeout.new("rum_em_test timed out after #{timeout} seconds")
            rescue Exception => e
              @last_exception = e
            end
            # assume test block is deadlocked; reset the running flag to allow
            # EM.stop to interrupt the test block (on deferred thread).
            @em_test_block_running = false
            stop
          end
          if defer
            EM.defer(&tester)
          else
            tester.call
          end
        end

        # require tester to call stop properly (i.e. call stop_em_test)
        assert_em_test_not_running
        raise "Test was still stopping after EM block" unless @em_test_stopping
        raise "Test was not stopped after EM block" unless @em_test_stopped

        # Reraise with full backtrace for debugging purposes
        # This assumes the exception class accepts a single string on construction
        if @last_exception
          message = "#{@last_exception.message}\n#{@last_exception.backtrace.join("\n")}"
          if @last_exception.class == ArgumentError
            raise ArgumentError, message
          else
            begin
              raise @last_exception.class, message
            rescue ArgumentError
              # exception class does not support single string construction.
              message = "#{@last_exception.class}: #{message}"
              raise message
            end
          end
        end
        true
      ensure
        # reset
        @em_test_block_running = false
        @em_test_stopping = false
        @em_test_stopped = false
      end

      # stops EM in a thread-safe manner.
      def self.stop
        unless @em_test_stopping
          @em_test_stopping = true
          EM.next_tick { inner_stop }
        end
        true
      end

      # checks that proper stop mechanism is called by all tests.
      def self.assert_em_test_not_running
        raise "Test block is still running; call stop_em_test instead of EM.stop" if @em_test_block_running
      end

      private

      # invokes EM tests in a thread-safe manner.
      def self.do_test(&callback)
        callback.call
      rescue Exception => e
        @last_exception = e unless @last_exception
      ensure
        @em_test_block_running = false
      end

      def self.inner_stop
        EM.next_tick do
          # wait for tester callback to return before attempting to stop EM. the
          # issue is that deferred callbacks are still being handled by EM and
          # will raise exceptions on the defer thread if EM is stopped before
          # the deferred block returns.
          if @em_test_block_running
            inner_stop
          elsif !@em_test_stopped
            @em_test_stopped = true
            EM.stop
          end
        end
      end
    end # EmTestRunner

    # Runs the given block in an EM loop with exception handling to ensure
    # deferred code is rescued and printed to console properly on error
    #
    # === Parameters
    # options[:defer](Fixnum):: true to defer (default), false to run once EM starts
    # options[:timeout](Fixnum):: timeout in seconds or 5
    #
    # === Block
    # block to call for test
    #
    # === Return
    # always true
    def run_em_test(options = nil, &callback)
      EmTestRunner.run(options, &callback)
    end

    # stops EM test safely by ensuring EM.stop is only called once on the main
    # thread after the test block (usually deferred) has returned.
    def stop_em_test
      EmTestRunner.stop
    end

  end # SpecHelper

end # RightScale

# Monkey patch spec reporter to dump logged errors to console only on spec
# failure.
#
# FIX: support rspec v2.6.x+
raise "RightLink specs require rspec v1.3.x" unless defined?(::Spec::Runner::Reporter)
module Spec
  module Runner
    class Reporter
      class Failure
        unless method_defined?(:header_for_right_link_spec)

          alias :initialize_for_right_link_spec :initialize
          def initialize(group_description, example_description, exception)
            initialize_for_right_link_spec(group_description, example_description, exception)
            @errors = ::RightScale::Log.errors
          end

          alias :header_for_right_link_spec :header
          def header
            default_header = header_for_right_link_spec
            return "#{default_header}\n=== Begin dump of logged errors ===\n#{@errors}\n=== End dump of logged errors ===" if @errors
            return default_header
          end

        end
      end
    end
  end
end

module RightScale
  class Log
    unless self.respond_to?(:method_missing_for_right_link_spec)
      # Monkey patch RightLink logger to not log by default
      # Define env var RS_LOG to override this behavior and have
      # the logger log normally
      class << self
        alias :method_missing_for_right_link_spec :method_missing
      end

      @@error_io = nil

      def self.method_missing(m, *args)
        unless [:debug, :info, :warn, :warning, :error, :fatal].include?(m) && ENV['RS_LOG'].nil?
          method_missing_for_right_link_spec(m, *args)
        end
      end

      def self.error(message, exception = nil, backtrace = :caller)
        @@error_io.puts(::RightScale::Log.format(message, exception, backtrace)) if @@error_io
        logger.error(message, exception, backtrace) if ENV['RS_LOG']
      end

      def self.has_errors?
        return @@error_io && @@error_io.pos > 0
      end

      def self.errors
        return nil unless has_errors?
        result = @@error_io.string
        @@error_io = nil
        return result
      end

      def self.reset_errors
        @@error_io = StringIO.new
      end

    end
  end
end

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'instance_state'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'cook', 'chef_state'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'cook', 'cook_state'))

module RightScale
  class InstanceState
    def self.update_logger
      true
    end

    def self.update_motd
      true
    end
  end
end

# Monkey patch to reduce how often ohai is invoked during spec test. we don't
# need realtime info, so static info should be good enough for testing. This
# is important on Windows for speed but also on Ubuntu to work around an ohai
# issue where multiple invocations of the ohai/plugins/passwd.rb plugin
# invokes Etc which appears to leak a system resource and cause a segmentation
# fault.
begin
  require 'chef/client'
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'chef', 'ohai_setup'))

  # text for a temporary plugin used to verify custom plugins are being loaded.
  TEST_PLUGIN_TEXT = <<EOF
provides "rightscale_test_plugin"
rightscale_test_plugin Mash.new
rightscale_test_plugin[:test_value] = 'abc'
EOF

  class Chef
    class Client

      def run_ohai
        unless defined?(@@ohai)
          # Create temporary plugin file for testing; doing this here because
          # loading ohai takes a long time and we only want to do it once during
          # testing. There is no guarantee that the test verifying this plugin
          # will actually be run at some point.
          plugin_rb_path = File.join(RightScale::OhaiSetup::CUSTOM_PLUGINS_DIR_PATH, "rightscale_test_plugin.rb")
          File.open(plugin_rb_path, "w") { |f| f.write(TEST_PLUGIN_TEXT) }
          begin
            RightScale::OhaiSetup.configure_ohai
            @@ohai = Ohai::System.new
            @@ohai.all_plugins
          ensure
            File.delete(plugin_rb_path) rescue nil
          end
        end
        @ohai = @@ohai
      end
    end
  end
rescue LoadError
  #do nothing; if Chef isn't loaded, then no need to monkey patch
end

module RightScale
  class PayloadFactory
    # build a bundle based on the provided named arguments.  Uses common defaults for some params
    def self.make_bundle(opts={})
      defaults = {
        :executables           => [],
        :cookbook_repositories => [],
        :audit_id              => 1234,
        :full_converge         => nil,
        :cookbooks             => nil,
        :repose_servers        => ["a-repose-server"],
        :dev_cookbooks         => nil,
        :runlist_policy        => RightScale::RunlistPolicy.new(nil, nil)
      }

      bundle_opts = defaults.merge(opts)

      RightScale::ExecutableBundle.new(bundle_opts[:executables],
                                       bundle_opts[:cookbook_repositories],
                                       bundle_opts[:audit_id],
                                       bundle_opts[:full_converge],
                                       bundle_opts[:cookbooks],
                                       bundle_opts[:repose_servers],
                                       bundle_opts[:dev_cookbooks],
                                       bundle_opts[:runlist_policy])
    end
  end
end

shared_examples_for 'mocks state' do
  include RightScale::SpecHelper

  before(:each) do
    setup_state
  end

  after(:each) do
    cleanup_state
  end
end

shared_examples_for 'mocks shutdown request' do

  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance'))

  before(:each) do
    @mock_shutdown_request = ::RightScale::ShutdownRequest.new
    flexmock(::RightScale::ShutdownRequest).should_receive(:instance).and_return(@mock_shutdown_request)
  end
end

shared_examples_for 'mocks shutdown request proxy' do

  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'cook'))

  before(:each) do
    ::RightScale::ShutdownRequestProxy.init(nil)  # nil command client for unit testing
    @mock_shutdown_request = ::RightScale::ShutdownRequestProxy.new
    flexmock(::RightScale::ShutdownRequestProxy).should_receive(:instance).and_return(@mock_shutdown_request)
  end
end

shared_examples_for 'mocks metadata' do
  before(:each) do
    # mock the metadata and user data
    @output_dir_path = File.join(Dir.tmpdir, 'rs_mock_metadata')
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    RightScale::AgentConfig.cloud_state_dir = File.join(@output_dir_path, 'var', 'spool')
    FileUtils.mkdir_p(File.join(RightScale::AgentConfig.cloud_state_dir, 'none'))
    FileUtils.touch([File.join(RightScale::AgentConfig.cloud_state_dir, 'user-data.rb'),
                     File.join(RightScale::AgentConfig.cloud_state_dir, 'none', 'user-data.txt')])

    # need to ensure mocked EC2_INSTANCE_ID is nil when loaded from cache to
    # avoid breaking specs which expect no initial state. the problem is that
    # some existing specs load the real cloud metadata cache on the CI machine
    # and it's hard to ensure that they don't leak into other specs.
    ::File.open(File.join(RightScale::AgentConfig.cloud_state_dir, 'meta-data-cache.rb'), "w") do |f|
      f.puts "ENV['EC2_INSTANCE_ID'] = nil"
    end

    mock_state_dir_path = File.join(@output_dir_path, 'etc', 'rightscale.d')
    mock_cloud_file_path = File.join(mock_state_dir_path, 'cloud')
    flexmock(RightScale::AgentConfig, :cloud_file_path => mock_cloud_file_path)

    FileUtils.mkdir_p(mock_state_dir_path)
    File.open(File.join(mock_cloud_file_path), 'w') { |f| f.puts "none" }
  end

  after(:each) do
    FileUtils.rm_rf(@output_dir_path) if File.directory?(@output_dir_path)
    @output_dir_path = nil
  end
end

# global spec configuration.
::Spec::Runner.configure do |config|
  config.before(:each) { ::RightScale::Log.reset_errors }
  config.after(:each) do
    # ensure all tests clean up their EM resources
    queue = EM.instance_variable_get(:@next_tick_queue)
    (queue.nil? || queue.empty?).should be_true
  end
end
