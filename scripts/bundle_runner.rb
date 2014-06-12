#
# Copyright (c) 2009-2014 RightScale Inc
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


require 'rubygems'
require 'trollop'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'
require 'right_agent/core_payload_types'
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))

module RightScale

  class BundleRunner
    include CommandHelper

    def cmd_name
      raise "Please initialize @cmd_name" unless @cmd_name
      @cmd_name
    end

    def type
      raise "Please initialize @type" unless @type
      @type
    end

    # Default number of seconds to wait for command response
    DEFAULT_TIMEOUT = 60

    # Run recipe or RightScript (that is, schedule it)
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Block
    # If a block is given, it should take one argument corresponding to the
    # reply sent back by the agent
    #
    # === Return
    # true:: If everything went smoothly
    # false:: If something terrible happened
    def run(options, &callback)
      fail('Missing identity or name argument', true) unless options[:id] || options[:name]

      fail_if_right_agent_is_not_running

      echo(options)
      cmd = { :name => cmd_name, :options => to_forwarder_options(options) }
      AgentConfig.cfg_dir = options[:cfg_dir]

      exit_code = true
      callback ||= lambda do |r|
        response = serialize_operation_result(r) rescue nil
        if r == 'OK'
          puts "Request sent successfully"
        elsif response.respond_to?(:success?) && response.success?
          puts "Request processed successfully"
        else
          puts "Failed to process request (#{(response.respond_to?(:content) && response.content) || '<unknown error>'})"
          exit_code = false
        end
      end

      begin
        check_privileges
        timeout = options[:timeout] || DEFAULT_TIMEOUT
        send_command(cmd, options[:verbose], timeout) { |r| callback.call(r) }
      rescue Exception => e
        fail(e.message)
      end
      exit_code
    rescue SystemExit => e
      raise e
    rescue Exception => e
      fail(e)
    end

    # Echo what is being requested
    #
    # === Parameters
    # options(Hash):: Options specified
    #
    # === Return
    # true:: Always return true
    def echo(options)
      which = options[:id] ? "with ID #{options[:id].inspect}" : "named #{format_script_name(options[:name])}"
      scope = options[:scope] == :all ? "'all' servers" : "a 'single' server"
      where = options[:tags] ? "on #{scope} with tags #{options[:tags].inspect}" : "locally on this server"
      using = ""
      if options[:parameters] && !options[:parameters].empty?
        using = " using parameters #{options[:parameters].inspect}"
      end
      if options[:json]
        using += !using.empty? && options[:json_file] ? " and " : " using "
        using += "options from JSON file #{options[:json_file].inspect}"
      end

      if options[:thread]
        thread = " on thread #{options[:thread]}"
      else
        thread = ""
      end

      if options[:policy]
        policy = " auditing on policy #{options[:policy]}"
      else
        policy = ""
      end
      puts "Requesting to execute the #{type} #{which} #{where}#{using}#{thread}#{policy}"
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args(arguments=ARGV)
      options = { :attributes => {}, :parameters => {}, :verbose => false }

      parser = Trollop::Parser.new do
        opt :id, "", :type => String, :long => "--identity", :short => "-i"
        opt :name, "", :type => String
        opt :parameter, "", :type => :string, :multi => true, :short => "-p"
        opt :thread, "", :type => String
        opt :json_file, "", :type => String, :short => "-j", :long => "--json"
        opt :tags, "", :type => String, :short => "-r", :long => "--recipient_tags"
        opt :scope, "", :type => String, :default => "all"
        opt :cfg_dir, "", :type => String
        opt :policy, "", :type => String, :short => "-P"
        opt :audit_period, "", :type => :int, :long => "--audit_period"
        opt :timeout, "", :type => :int, :short => "-T", :default => DEFAULT_TIMEOUT
        opt :verbose
        version ""
      end

      parse do
        options.merge!(parser.parse(arguments))
        options.delete(:name) if options[:id]

        if options[:parameter]
          options.delete(:parameter).each do |p|
            name, value = p.split('=', 2)
            if name && value && value.include?(':')
              options[:parameters][name] = value
            else
              fail("Invalid parameter definition '#{p}', should be of the form 'name=type:value'")
            end
          end
        end

        if options[:json_file]
          fail("Invalid JSON filename '#{options[:json_file]}'") unless File.file?(options[:json_file])
          begin
            options[:json] = IO.read(options[:json_file])
          rescue Exception => e
            fail("Invalid JSON content: #{e}")
          end
        end

        options[:tags] = options[:tags].split if options[:tags]

        if options[:scope]
          if options[:scope] == 'single'
            options[:scope] = :any
          elsif options[:scope] == 'all'
            options[:scope] = :all
          else
            fail("Invalid scope definition '#{options[:scope]}', should be either 'single' or 'all'")
          end
        end

        if options[:thread] && (options[:thread] !~ RightScale::AgentConfig.valid_thread_name)
          fail("Invalid thread name #{options[:thread]}", true)
        end

        options
      end
    end

    protected


    # Map arguments options into forwarder actor compatible options
    #
    # === Parameters
    # options(Hash):: Arguments options
    #
    # === Return
    # result(Hash):: Forwarder actor compatible options hash
    def to_forwarder_options(options)
      result = {}
      if options[:tags]
        result[:tags] = options[:tags]
        result[:selector] = options[:scope]
      end
      if options[:thread]
        result[:thread] = options[:thread]
      end
      if options[:policy]
        result[:policy] = options[:policy]
      end
      if options[:audit_period]
        result[:audit_period] = options[:audit_period]
      end

      result
    end

    def format_script_name(script_name)
      script_name && script_name.include?("'") ? "\"#{script_name}\"" : "'#{script_name}'"
    end

  end # BundleRunner

end # RightScale