# === Synopsis:
#   RightScale Tagger (rs_tag)
#   (c) 2011 RightScale
#
#   Tagger allows listing, adding and removing tags on the current instance and
#   querying for all instances with a given set of tags
#
# === Examples:
#   Retrieve all tags:
#     rs_tag --list
#     rs_tag -l
#
#   Add tag 'a_tag' to instance:
#     rs_tag --add a_tag
#     rs_tag -a a_tag
#
#   Remove tag 'a_tag':
#     rs_tag --remove a_tag
#     rs_tag -r a_tag
#
#   Retrieve all instances with all of the tags in a set:
#     rs_tag --query "a_tag b_tag"
#     rs_tag -q "a_tag b_tag"
#
# === Usage
#    rs_tag (--list, -l | --add, -a TAG | --remove, -r TAG | --query, -q TAG_LIST)
#
#    Options:
#      --list, -l           List current server tags
#      --add, -a TAG        Add tag named TAG
#      --remove, -r TAG     Remove tag named TAG
#      --query, -q TAG_LIST Query for all instances that have any of the tags in TAG_LIST
#                           with the TAG_LIST being quoted if it contains spaces
#      --die, -e            Exit with error if query/list fails
#      --format, -f FMT     Output format: json, yaml, text
#      --verbose, -v        Display debug information
#      --help:              Display help
#      --version:           Display version information
#
$:.push(File.dirname(__FILE__))

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common', 'serializer'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common', 'serializable'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'command_protocol', 'lib', 'command_protocol'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'actors', 'lib', 'agent_manager'))
require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'rdoc_patch'
require 'agent_utils'
require 'json'

module RightScale

  class Tagger

    class TagError < Exception
      attr_reader :code

      def initialize(msg, code=nil)
        super(msg)
        @code = code || 1
      end
    end

    include Utils

    VERSION = [0, 1]

    # Manage instance tags
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      if options[:verbose]
        log = Logger.new(STDERR)
      else
        log = Logger.new(StringIO.new)
      end
      RightScale::RightLinkLog.force_logger(log)

      unless options.include?(:action)
        STDERR.puts "Missing argument, rs_tag --help for additional information"
        fail(1)
      end
      cmd = { :name => options[:action] }
      cmd[:tag] = options[:tag] if options[:tag]
      cmd[:tags] = options[:tags] if options[:tags]
      cmd[:query] = options[:query] if options[:query]
      config_options = agent_options('instance')
      listen_port = config_options[:listen_port]
      raise ArgumentError.new('Could not retrieve agent listen port') unless listen_port
      command_serializer = Serializer.new
      client = CommandClient.new(listen_port, config_options[:cookie])
      begin
        @disposition = nil

        client.send_command(cmd, options[:verbose]) do |res|
          if options[:action] == :get_tags
            if res.empty?
              if options[:die]
                @disposition = TagError.new('No server tags found', 44)
              else
                puts format_output([], options[:format])
                @disposition = 0
              end
            else
              puts format_output(res, options[:format])
              @disposition = 0
            end
          elsif options[:action] == :query_tags
            r = OperationResult.from_results(command_serializer.load(res))
            if r.success?
              if r.content.empty?
                if options[:die]
                  @disposition = TagError.new("No servers with tags #{options[:tags].inspect}", 44)
                else
                  puts format_output({}, options[:format])
                  @disposition = 0
                end
              else
                puts format_output(r.content, options[:format])
                @disposition = 0
              end
            else
              @disposition = TagError.new("Tag query failed: #{r.content}", 53)
            end
          else
            STDERR.puts res
            @disposition = 0
          end
        end
      rescue Exception => e
        @disposition = e
      end

      pass while @disposition.nil?
      case @disposition
        when 0
          succeed
        else
          fail(@disposition)
      end
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      options = { :verbose => false }

      opts = OptionParser.new do |opts|

        opts.on('-l', '--list') do
          options[:action] = :get_tags
        end

        opts.on('-a', '--add TAG') do |t|
          options[:action] = :add_tag
          options[:tag] = t
        end

        opts.on('-r', '--remove TAG') do |t|
          options[:action] = :remove_tag
          options[:tag] = t
        end

        opts.on('-q', '--query TAG_LIST') do |t|
          options[:action] = :query_tags
          options[:tags] = t.split
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
        end

        opts.on('-e', '--die') do
          options[:die] = true
        end

        opts.on('-f', '--format FMT') do |fmt|
          options[:format] = fmt
        end
      end

      opts.on_tail('--version') do
        puts version
        succeed
      end

      opts.on_tail('--help') do
         RDoc::usage_from_file(__FILE__)
         succeed
      end

      begin
        opts.parse!(ARGV)
      rescue Exception => e
        STDERR.puts e.message + "\nUse rs_tag --help for additional information"
        fail(1)
      end
      options
    end

protected
    # Format output for display to user
    #
    # === Parameter
    # result(Object):: JSON-compatible data structure (array, hash, etc)
    # format(String):: how to print output - json, yaml, text
    #
    # === Return
    # a String containing the specified output format
    def format_output(result, format)
      case format
        when /^jso?n?$/, nil
          JSON.pretty_generate(result)
        when /^ya?ml$/
          YAML.dump(result)
        when /^te?xt$/, /^sh(ell)?/, 'list'
          result = result.keys if result.respond_to?(:keys)
          result.join(" ")
        else
          raise ArgumentError, "Unknown output format #{format}"
      end
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
    # msg(String):: Error message, default to nil (no message printed)
    # print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(reason=nil, options={})
      case reason
      when TagError
        STDERR.puts reason.message
        code = reason.code
      when Exception
        STDERR.puts reason.message
        code = 50
      when String
        STDERR.puts reason
        code = 50
      when Integer
        code = reason
      else
        code = 1
      end

      RDoc::usage_from_file(__FILE__) if options[:print_usage]
      exit(code)
    end

    # Version information
    #
    # === Return
    # ver(String):: Version information
    def version
      ver = "rs_tag #{VERSION.join('.')} - RightLink's tagger (c) 2011 RightScale"
    end

  end
end

#
# Copyright (c) 2011 RightScale Inc
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
