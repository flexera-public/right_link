require 'rubygems'
require 'ostruct'

# Setup debugger if necessary
# To remote debug cook, run the spec with 'COOK_DEBUG=1234 spec ...' then attach the
# remote ruby debugger to port 1234
if port = ENV.delete('COOK_DEBUG')
  require 'ruby-debug-ide'
  Debugger::ARGV = ARGV.clone
  Debugger::PROG_SCRIPT = __FILE__

  options = OpenStruct.new(
    'frame_bind'  => false,
    'host'        => nil,
    'load_mode'   => false,
    'port'        => port.to_i,
    'stop'        => true,
    'tracing'     => false
  )
  trap('INT') { Debugger.interrupt_last }

  # set options
  Debugger.keep_frame_binding = options.frame_bind
  Debugger.tracing = options.tracing

  # debug!
  Debugger.debug_program(options)
end

require 'eventmachine'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'cook'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'providers'))

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'agent_test_config'))

# Disable 'constant already defined' warnings so cook process doesn't output to stderr
$VERBOSE=nil

RightScale::Log.log_to_file_only(true) # Used by integration tests
RightScale::Cook.const_set(:AGENT_NAME, ENV['RS_AGENT']) if ENV['RS_AGENT']

module RightScale

  class ExecutableSequence

    # Use forced location of scripts cache and state files in cook process that was setup in instance
    # by monkey patched InstanceState in test version of instance_setup.rb
    alias :original_initialize :initialize
    def initialize(bundle)
      agent_identity = nil
      File.open(AgentTestConfig.agent_identity_file,"r"){|f| agent_identity = f.gets.chomp }
      RightScale::AgentConfig.cache_dir = AgentTestConfig.cache_path(agent_identity)
      RightScale::CookState.const_set(:STATE_FILE, AgentTestConfig.cook_state_file)
      FileUtils.mkdir_p(RightScale::AgentConfig.cache_dir)
      original_initialize(bundle)
    end

    # Load test cookbooks
    alias :original_configure_chef :configure_chef
    def configure_chef
      begin
        original_configure_chef
        Chef::Config[:cookbook_path] << File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
        file_cache_path = File.join(AgentConfig.cache_dir, 'chef')
        Chef::Config[:file_cache_path] = file_cache_path
        Chef::Config[:cache_options] ||= {}
        Chef::Config[:cache_options][:path] = File.join(file_cache_path, 'checksums')
        FileUtils.mkdir_p(Chef::Config[:file_cache_path])
        FileUtils.mkdir_p(Chef::Config[:cache_options][:path])
      rescue Exception => e
        RightScale::Log.error("Failed to configure chef", e, :trace)
      end
      true
    end

    #
    alias :original_download_repos :download_repos
    def download_repos
      true
    end
  end
end

load File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'instance', 'right_link', 'agents', 'lib', 'instance', 'cook.rb'))

RightScale::Cook.new.run
