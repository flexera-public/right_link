# === Synopsis:
#   RightScale Bundle Runner (rs_run_right_script/rs_run_recipe) - (c) 2009-2011 RightScale Inc
#
#   rs_run_right_script and rs_run_recipe are command line tools that allow
#   running RightScripts and recipes respectively from within an instance
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
# === Usage:
#    rs_run_recipe --identity, -i ID [--json, -j JSON_FILE] [--verbose, -v]
#    rs_run_recipe --name, -n NAME [--json, -j JSON_FILE]
#                  [--recipient_tags, -r TAG_LIST]
#                  [--scope, -s SCOPE] [--verbose, -v]
#    rs_run_right_script --identity, -i ID [--parameter, -p NAME=type:VALUE]*
#                  [--verbose, -v]
#    rs_run_right_script --name, -n NAME [--parameter, -p NAME=type:VALUE]*
#                  [--recipient_tags, -r TAG_LIST]
#                  [--scope, -s SCOPE] [--verbose, -v]
#
#      * Can appear multiple times
#
#    Options:
#      --identity, -i ID     RightScript or ServerTemplateChefRecipe id
#      --name, -n NAME       RightScript or Chef recipe name (overridden by id)
#      --json, -j JSON_FILE  JSON file name for JSON to be merged into
#                              attributes before running recipe
#      --parameter,
#        -p NAME=TYPE:VALUE  Define or override RightScript input
#                              Note: Only applies to run_right_script
#      --thread,             Schedule the operation on a specific thread name
#        -t THREAD             for concurrent execution. Thread names must begin
#                              with a letter and can consist only of lower-case
#                              alphabetic characters, digits, and the underscore
#                              character.
#      --recipient_tags,     Tags for selecting which instances are to receive
#                              request with the TAG_LIST being quoted if it
#        -r TAG_LIST           contains spaces
#      --scope, -s SCOPE     Scope for selecting tagged recipients: single or
#                              all (default all)
#      --cfg-dir, -c DIR     Set directory containing configuration for all
#                              agents
#      --verbose, -v         Display progress information
#      --help:               Display help
#
#    Note: Partially specified option names are accepted if not ambiguous.

require 'rubygems'
require 'optparse'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'
require 'right_agent/core_payload_types'

module RightScale

  class BundleRunner

    # Default number of seconds to wait for command response
    DEFAULT_TIMEOUT = 20

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
    # true:: Always return true
    def run(options, &callback)
      fail('Missing identity or name argument', true) unless options[:id] || options[:name]
      if options[:thread] && (options[:thread] !~ RightScale::ExecutableBundle::VALID_THREAD_NAME)
        fail("Invalid thread name #{options[:thread]}", true)
      end
      echo(options)
      cmd = { :options => to_forwarder_options(options) }
      cmd[:name] = options[:bundle_type] == :right_script ? 'run_right_script' : 'run_recipe'
      AgentConfig.cfg_dir = options[:cfg_dir]
      config_options = AgentConfig.agent_options('instance')
      listen_port = config_options[:listen_port]
      fail('Could not retrieve listen port', false) unless listen_port
      command_serializer = Serializer.new
      client = CommandClient.new(listen_port, config_options[:cookie])

      callback ||= lambda do |r|
        response = OperationResult.from_results(command_serializer.load(r)) rescue nil
        if r == 'OK'
          puts "Request sent successfully"
        elsif response.respond_to?(:success?) && response.success?
          puts "Request processed successfully"
        else
          puts "Failed to process request: #{(response.respond_to?(:content) && response.content) || '<unknown error>'}"
        end
      end

      begin
        timeout = options[:timeout] || DEFAULT_TIMEOUT
        client.send_command(cmd, options[:verbose], timeout) { |r| callback.call(r) }
      rescue Exception => e
        fail(e.message)
      end
      true
    end

    # Echo what is being requested
    #
    # === Parameters
    # options(Hash):: Options specified
    #
    # === Return
    # true:: Always return true
    def echo(options)
      type = options[:bundle_type] == :right_script ? "RightScript" : "recipe"
      which = options[:id] ? "with ID #{options[:id].inspect}" : "named #{options[:name].inspect}"
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
      puts "Requesting to execute the #{type} #{which} #{where}#{using}"
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :attributes => {}, :parameters => {}, :scope => :all, :verbose => false }

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

        opts.on('t', '--thread THREAD') do |p|
          options[:thread] = p
        end

        opts.on('-j', '--json JSON_FILE') do |f|
          fail("Invalid JSON filename '#{f}'") unless File.file?(f)
          options[:json_file] = f
          begin
            options[:json] = IO.read(f)
          rescue Exception => e
            fail("Invalid JSON content: #{e}")
          end
        end

        opts.on('-r', '--recipient_tags TAG_LIST') do |t|
          options[:tags] = t.split
        end

        opts.on('-s', '--scope SCOPE') do |s|
          if s == 'single'
            options[:scope] = :any
          elsif s == 'all'
            options[:scope] = :all
          else
            fail("Invalid scope definition '#{s}', should be either 'single' or 'all'")
          end
        end

        opts.on("-c", "--cfg-dir DIR") do |d|
          options[:cfg_dir] = d
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
        end

        opts.on_tail('--help') do
           puts Usage.scan(__FILE__)
           exit
        end

      end

      begin
        opts.parse!(ARGV)
      rescue Exception => e
        puts e.message + "\nUse --help for additional information"
        exit(1)
      end
      options
    end

protected

    # Print error on console and exit abnormally
    #
    # === Parameter
    # msg(String):: Error message, default to nil (no message printed)
    # print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      puts Usage.scan(__FILE__) if print_usage
      exit(1)
    end

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
      if options[:bundle_type] == :right_script
        result[:right_script_id] = options[:id] if options[:id]
        result[:right_script]    = options[:name] if options[:name] && !options[:id]
        result[:arguments]       = options[:parameters] unless options[:parameters].empty?
      else
        result[:recipe_id] = options[:id] if options[:id]
        result[:recipe]    = options[:name] if options[:name] && !options[:id]
        result[:json]      = options[:json]
      end
      result
    end

  end # BundleRunner

end # RightScale

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
