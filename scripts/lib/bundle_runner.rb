# === Synopsis:
#   RightScale Bundle Runner (rs_run_right_script/rs_run_recipe)
#   (c) 2009 RightScale
#
#   rs_run_right_script and rs_run_recipe are command line tools that allow
#   running RightScripts and recipes respectively from within an instance.
#
# === Examples:
#   Run recipe with id 12:
#     rs_run_recipe -i 12
#     rs_run_recipe --identity 12
#
#   Run recipe 'nginx' using given JSON attributes file:
#     rs_run_recipe -n nginx -j attribs.js
#     rs_run_recipe --name nginx --json attribs.js
#
#   Run RightScript with id 14 and override input 'APPLICATION' with value 
#   'Mephisto':
#     rs_run_right_script -i 14 -p APPLICATION=text:Mephisto
#     rs_run_right_script --identity 14 --parameter APPLICATION=text:Mephisto
#
#  === Usage:
#    rs_run_recipe --identity, -i ID [--json, -j JSON_FILE] [--verbose, -v]
#    rs_run_recipe --name, -n NAME [--json, -j JSON_FILE] [--verbose, -v]
#    rs_run_right_script --identity, -i ID [--parameter, -p NAME=type:VALUE]* [--verbose, -v]
#    rs_run_right_script --name, -n NAME [--parameter, -p NAME=type:VALUE]* [--verbose, -v]
#
#      * Can appear multiple times
#
#    Options:
#      --identity, -id ID   RightScript or ServerTemplateChefRecipe id
#      --name, -n NAME      RightScript or Chef recipe name (overriden by id)
#      --json, -j JSON_FILE JSON file name for JSON to be merged into
#                           attributes before running recipe
#      --parameter,
#        -p NAME=type:VALUE Define or override RightScript input
#                             Note: Only applies to run_right_script
#      --verbose, -v        Display progress information
#      --help:              Display help
#      --version:           Display version information

$:.push(File.dirname(__FILE__))
require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'yaml'
require 'rdoc_patch'
require 'agent_utils'
require 'nanite'
require File.join(File.dirname(__FILE__), '..', '..', 'lib', 'command_protocol', 'lib', 'command_protocol')
require File.join(File.dirname(__FILE__), '..', '..', 'agents', 'lib', 'common_lib')

module RightScale

  class BundleRunner

    VERSION = [0, 1]

    # Run recipe or RightScript (that is, schedule it)
    #
    # === Parameters
    # options<Hash>:: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      fail('Missing identity or name argument', true) unless options[:id] || options[:name]
      port       = CommandConstants::SOCKET_PORT + 1
      listening  = false
      retries    = 0
      cmd        = { :options => to_forwarder_options(options), :port => port }
      cmd[:name] = options[:bundle_type] == :right_script ? 'run_right_script' : 'run_recipe'
      error      = nil

      EM.run do
        while !listening && retries < 10 do
          puts "Trying to start server on port #{port}" if options[:verbose]
          begin
            EM.start_server('0.0.0.0', port, ReplyHandler, options)
            listening = true
          rescue Exception => e
            error = e
            retries += 1
            port += 1
          end
          if listening
            puts "Server listening on port #{port}" if options[:verbose]
            EM.connect('0.0.0.0', RightScale::CommandConstants::SOCKET_PORT, SendHandler, cmd, options)
            EM.add_timer(20) { EM.stop; fail('Timed out waiting for instance agent reply') }
          end 
        end
      end
      puts "Could not start server: #{error && error.message || 'unknown error'}" unless listening
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options<Hash>:: Hash of options as defined by the command line
    def parse_args
      options = { :attributes => {}, :parameters => {}, :verbose => false }

      opts = OptionParser.new do |opts|

       opts.on('-i', '--identity ID') do |id|
         options[:id] = id
       end

       opts.on('-n', '--name NAME') do |n|
         options[:name] = n unless options[:id]
       end

        opts.on('-p', '--parameter PARAM_DEF') do |p|
          name, value = p.split('=')
          if name && value && value.include?(':')
            options[:parameters][name] = value
          else
            fail("Invalid parameter definition '#{p}', should be of the form 'name=type:value'")
          end
        end

        opts.on('-j', '--json JSON_FILE') do |f|
          fail("Invalid JSON filename '#{f}'") unless File.file?(f)
          begin
            options[:json] = JSON.load(IO.read(f))
          rescue Exception => e
            fail("Invalid JSON content: #{e.message}")
          end
        end

       opts.on('-v', '--verbose') do
         options[:verbose] = true
       end

       opts.on_tail('--help') do
          RDoc::usage_from_file(__FILE__)
          exit
        end
      end

      opts.on_tail('--version') do
        puts version
        exit
      end

      opts.parse!(ARGV)
      options
    end

protected

    # Print error on console and exit abnormally
    #
    # === Parameter
    # msg<String>:: Error message, default to nil (no message printed)
    # print_usage<Boolean>:: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      RDoc::usage_from_file(__FILE__) if print_usage
      exit(1)
    end

    # Map arguments options into forwarder actor compatible options
    #
    # === Parameters
    # options<Hash>:: Arguments options
    #
    # === Return
    # opts<Hash>:: Forwarder actor compatible options hash
    def to_forwarder_options(options)
      opts = {}
      if options[:bundle_type] == :right_script
        opts[:right_script_id] = options[:id] if options[:id]
        opts[:right_script]    = options[:name] if options[:name] && !options[:id]
        opts[:arguments]       = options[:parameters]
      else
        opts[:recipe_id] = options[:id] if options[:id]
        opts[:recipe]    = options[:name] if options[:name] && !options[:id]
        opts[:json]      = options[:json]
      end
      opts
    end

# options[:token_id]<Integer>:: Instance API token id
  # options[:account_id]<Integer>:: Account id
  # options[:right_script_id]<Integer>:: Script id
  # options[:arguments]<Hash>:: Serialized script execution arguments values keyed by name
  #
  # === Return
  # true:: Always return true
  def schedule_right_script(options)
    schedule_bundle(options)
  end

  # Forward Chef recipe scheduling request to instance agent
  #
  # === Parameters
  # options[:token_id]<Integer>:: Instance API token id
  # options[:account_id]<Integer>:: Account id, default to instance account
  # options[:recipe_id]<Integer>:: ServerTemplateChefRecipe id

    # Version information
    #
    # === Return
    # ver<String>:: Version information
    def version
      ver = "run_right_script/run_recipe #{VERSION.join('.')} - Interactive RightScript and Chef recipe scheduler (c) 2009 RightScale"
    end

  end

  # EventMachine connection handler which sends command to instance agent
  module SendHandler

    # Initialize command
    #
    # === Parameters
    # command<Hash>:: Command to be sent
    def initialize(command, options)
      @command = command
      @options = options
    end

    # Send command to instance agent
    # Called by EventMachine after connection with instance agent has been established
    #
    # === Return
    # true:: Always return true
    def post_init
      puts "Sending command #{@command.inspect}" if @options[:verbose]
      send_data(CommandSerializer.dump(@command))
      EM.next_tick { close_connection_after_writing }
      true
    end

  end

  # EventMachine connection handler which listens to agent output
  module ReplyHandler

    # Initialize parser
    def initialize(options)
      @options = options
      @parser = CommandParser.new { |data| puts data; EM.stop }
    end

    # Data available callback
    #
    # === Parameters
    # data<String>:: Output data
    #
    # === Return
    # true:: Always return true
    def receive_data(data)
      puts "Received raw data from agent: #{data}" if @options[:verbose] 
      @parser.parse_chunk(data)
      true
    end
  end

end 
