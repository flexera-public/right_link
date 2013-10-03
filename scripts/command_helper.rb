lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'right_link', 'version'))
require 'right_agent/scripts/usage'

module RightScale
  module CommandHelper
    def check_privileges
      config_options = ::RightScale::AgentConfig.agent_options('instance')
      pid_dir = config_options[:pid_dir]
      identity = config_options[:identity]
      raise ::ArgumentError.new('Could not get cookie file path') if (pid_dir.nil? & identity.nil?)
      cookie_file = File.join(pid_dir, "#{identity}.cookie")
      File.open(cookie_file, "r") { |f| f.close }
      true
    rescue Errno::EACCES => e
      fail(e)
    end
    # Creates a command client and sends the given payload.
    #
    # === Parameters
    # @param [Hash] cmd as a payload hash
    # @param [TrueClass, FalseClass] verbose flag
    # @param [TrueClass, FalseClass] timeout or nil
    #
    # === Block
    # @yield [response] callback for response
    # @yieldparam response [Object] response of any type
    def send_command(cmd, verbose, timeout=20)
      config_options = ::RightScale::AgentConfig.agent_options('instance')
      listen_port = config_options[:listen_port]
      raise ::ArgumentError.new('Could not retrieve agent listen port') unless listen_port
      client = ::RightScale::CommandClient.new(listen_port, config_options[:cookie])
      result = nil
      block = Proc.new do |res|
        result = res
        yield res if block_given?
      end
      client.send_command(cmd, verbose, timeout, &block)
      result
    end

    def serialize_operation_result(res)
      command_serializer = ::RightScale::Serializer.new
      ::RightScale::OperationResult.from_results(command_serializer.load(res))
    end

    # Exit with success.
    #
    # === Return
    # R.I.P. does not return
    def succeed
      exit(0)
    end

    # Print error on console and exit abnormally
    #
    # === Parameter
    # reason(Exception|String|Integer):: Exception, error message or numeric failure code
    #
    # === Return
    # R.I.P. does not return
    def fail(reason=nil, print_usage=false)
      case reason
      when Errno::EACCES
        STDERR.puts reason.message
        STDERR.puts "Try elevating privilege (sudo/runas) before invoking this command."
        code = 2
      when Exception
        STDERR.puts reason.message
        code = reason.respond_to?(:code) ? reason.code : 50
      when String
        STDERR.puts reason
        code = 50
      when Integer
        code = reason
      else
        code = 1
      end

      puts usage if print_usage
      exit(code)
    end

    def parse
      begin
        yield
      rescue Trollop::VersionNeeded
        STDOUT.puts(version)
        succeed
      rescue Trollop::HelpNeeded
        STDOUT.puts(usage)
        succeed
      rescue Trollop::CommandlineError => e
        STDERR.puts e.message + "\nUse --help for additional information"
        fail
      rescue SystemExit => e
        raise e
      end
    end

    def right_link_version
      RightLink.version
    end
  end
end
