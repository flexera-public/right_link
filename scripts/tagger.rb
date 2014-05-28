# === Synopsis:
#   RightScale Tagger (rs_tag) - (c) 2009-2014 RightScale Inc
#
#   Tagger allows listing, adding and removing tags on the current instance and
#   querying for instances with a given set of tags
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
#   Retrieve instances with any of the tags in a set each tag is a separate argument:
#     rs_tag --query "a_tag" "b:machine=tag" "c_tag with space"
#     rs_tag -q "a_tag" "b:machine=tag" "c_tag with space"
#
# === Usage
#    rs_tag (--list, -l | --add, -a TAG | --remove, -r TAG | --query, -q TAG[s])
#
#    Options:
#      --list, -l           List current server tags
#      --add, -a TAG        Add tag named TAG
#      --remove, -r TAG     Remove tag named TAG
#      --query, -q TAG[s]   Query for instances that have any of the TAG[s]
#                           with TAG being quoted if it contains spaces in it's value
#      --die, -e            Exit with error if query/list fails
#      --format, -f FMT     Output format: json, yaml, text
#      --verbose, -v        Display debug information
#      --help:              Display help
#      --version:           Display version information
#      --timeout, -t SEC    Custom timeout (default 60 sec)
#

require 'rubygems'
require 'trollop'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'
require File.normalize_path(File.join(File.dirname(__FILE__), 'command_helper'))

module RightScale

  class Tagger
    include CommandHelper

    TAG_REQUEST_TIMEOUT = 60

    class TagError < Exception
      attr_reader :code

      def initialize(msg, code=nil)
        super(msg)
        @code = code || 1
      end
    end

    def get_tags(res, options)
      raise TagError.new("List current server tags failed: #{res.inspect}", 45) unless res.kind_of?(Array)
      if res.empty?
        if options[:die]
          raise TagError.new('No server tags found', 44)
        else
          write_output(format_output([], options[:format]))
        end
      else
        write_output(format_output(res, options[:format]))
      end
    end

    def query_tags(res, options)
      r = serialize_operation_result(res)
      raise TagError.new("Query tags failed: #{r.inspect}", 46) unless r.kind_of?(OperationResult)
      if r.success?
        if r.content.nil? || r.content.empty?
          if options[:die]
            raise TagError.new("No servers with tags #{options[:tags].inspect}", 44)
          else
            write_output(format_output({}, options[:format]))
          end
        else
          write_output(format_output(r.content, options[:format]))
        end
      else
        raise TagError.new("Query tags failed: #{r.content}", 53)
      end
    end

    def add_tag(res, options)
      r = serialize_operation_result(res)
      raise TagError.new("Add tag failed: #{r.inspect}", 47) unless r.kind_of?(OperationResult)
      if r.success?
        write_error("Successfully added tag #{options[:tag]}")
      else
        raise TagError.new("Add tag failed: #{r.content}", 54)
      end
    end

    def remove_tag(res, options)
      r = serialize_operation_result(res)
      raise TagError.new("Remove tag failed: #{r.inspect}", 48) unless r.kind_of?(OperationResult)
      if r.success?
        write_output("Request processed successfully")
      else
        raise TagError.new("Remove tag failed: #{r.content}", 55)
      end
    end

    def build_cmd(options)
      cmd = { :name => options[:action] }
      cmd[:tag] = options[:tag] if options[:tag]
      cmd[:tags] = options[:tags] if options[:tags]
      cmd[:query] = options[:query] if options[:query]
      cmd
    end

    def set_logger(options)
      if options[:verbose]
        log = Logger.new(STDERR)
      else
        log = Logger.new(StringIO.new)
      end
      RightScale::Log.force_logger(log)
    end

    def missing_argument
      write_error("Missing argument, rs_tag --help for additional information")
      fail(1)
    end

    # Manage instance tags
    #
    # === Parameters
    # options(Hash):: Hash of options as defined in +parse_args+
    #
    # === Return
    # true:: Always return true
    def run(options)
      fail_if_right_agent_is_not_running
      check_privileges
      set_logger(options)
      missing_argument unless options.include?(:action)
      # Don't use send_command callback as it swallows exceptions by design
      res = send_command(build_cmd(options), options[:verbose], options[:timeout])

      case options[:action]
      when :get_tags
        get_tags(res, options)
      when :query_tags
        query_tags(res, options)
      when :add_tag
        add_tag(res, options)
      when :remove_tag
        remove_tag(res, options)
      else
        write_error(res)
      end
    rescue SystemExit => e
      raise e
    rescue Exception => e
      fail(e)
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Hash of options as defined by the command line
    def parse_args
      parser = Trollop::Parser.new do
        opt :list
        opt :add, "", :type => :string
        opt :remove, "", :type => :string
        opt :query, "", :type => :strings
        opt :verbose
        opt :die, "", :short => "-e"
        opt :format, "", :type => :string, :default => "json"
        opt :timeout, "", :type => :int, :default => TAG_REQUEST_TIMEOUT
        version ""
      end

      parse do
        options = parser.parse
        options[:action] = :get_tags if options.delete(:list)
        if options[:add]
          options[:action] = :add_tag
          options[:tag] = options.delete(:add).strip
          raise ::Trollop::CommandlineError.new("Non-empty value required") if options[:tag].empty?
        end
        if options[:remove]
          options[:action] = :remove_tag
          options[:tag] = options.delete(:remove).strip
          raise ::Trollop::CommandlineError.new("Non-empty value required") if options[:tag].empty?
        end
        if options[:query]
          options[:action] = :query_tags
          options[:tags] = options.delete(:query).map { |tag| tag.strip }
        end
        options[:format] = parse_format(options[:format])
        options
      end
    end

protected
    # Writes to STDOUT (and a placeholder for spec mocking).
    #
    # === Parameters
    # @param [String] message to write
    def write_output(message)
      STDOUT.puts(message)
    end

    # Writes to STDERR (and a placeholder for spec mocking).
    #
    # === Parameters
    # @param [String] message to write
    def write_error(message)
      STDERR.puts(message)
    end

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
      when :json
        JSON.pretty_generate(result)
      when :yaml
        YAML.dump(result)
      when :text
        result = result.keys if result.respond_to?(:keys)
        result.join(" ")
      else
        raise ArgumentError, "Unknown output format #{format}"
      end
    end

    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      "rs_tag #{right_link_version} - RightLink's tagger (c) 2009-2014 RightScale"
    end

    def usage
      Usage.scan(__FILE__)
    end

  end # Tagger

end # RightScale

#
# Copyright (c) 2014 RightScale Inc
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
