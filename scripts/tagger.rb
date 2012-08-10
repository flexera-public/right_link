# === Synopsis:
#   RightScale Tagger (rs_tag) - (c) 2009-2012 RightScale Inc
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
#      --timeout, -t        Custom timeout parameter (default 120 sec)
#

require 'rubygems'
require 'trollop'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

module RightScale

  class Tagger

    TAG_REQUEST_TIMEOUT = 2 * 60  # synchronous tag requests need a long timeout

    class TagError < Exception
      attr_reader :code

      def initialize(msg, code=nil)
        super(msg)
        @code = code || 1
      end
    end

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
      RightScale::Log.force_logger(log)

      unless options.include?(:action)
        write_error("Missing argument, rs_tag --help for additional information")
        fail(1)
      end
      cmd = { :name => options[:action] }
      cmd[:tag] = options[:tag] if options[:tag]
      cmd[:tags] = options[:tags] if options[:tags]
      cmd[:query] = options[:query] if options[:query]
     begin
        @disposition = nil
        send_command(cmd, options[:verbose], options[:timeout]) do |res|
          begin
            case options[:action]
            when :get_tags
              raise TagError.new("List current server tags failed: #{res.inspect}", 45) unless res.kind_of?(Array)
              if res.empty?
                if options[:die]
                  raise TagError.new('No server tags found', 44)
                else
                  write_output(format_output([], options[:format]))
                  @disposition = 0
                end
              else
                write_output(format_output(res, options[:format]))
                @disposition = 0
              end
            when :query_tags
              r = serialize_operation_result(res)
              raise TagError.new("Query tags failed: #{r.inspect}", 46) unless r.kind_of?(OperationResult)
              if r.success?
                if r.content.empty?
                  if options[:die]
                    raise TagError.new("No servers with tags #{options[:tags].inspect}", 44)
                  else
                    write_output(format_output({}, options[:format]))
                    @disposition = 0
                  end
                else
                  write_output(format_output(r.content, options[:format]))
                  @disposition = 0
                end
              else
                raise TagError.new("Query tags failed: #{r.content}", 53)
              end
            when :add_tag
              r = serialize_operation_result(res)
              raise TagError.new("Add tag failed: #{r.inspect}", 47) unless r.kind_of?(OperationResult)
              if r.success?
                write_error("Successfully added tag #{options[:tag]}")
                @disposition = 0
              else
                raise TagError.new("Add tag failed: #{r.content}", 54)
              end
            when :remove_tag
              r = serialize_operation_result(res)
              raise TagError.new("Remove tag failed: #{r.inspect}", 48) unless r.kind_of?(OperationResult)
              if r.success?
                write_error("Successfully removed tag #{options[:tag]}")
                @disposition = 0
              else
                raise TagError.new("Remove tag failed: #{r.content}", 55)
              end
            else
              write_error(res)
              @disposition = 0
            end
          rescue Exception => e
            @disposition = e
          end
        end
      rescue Exception => e
        @disposition = e
      end

      Thread.pass while @disposition.nil?
      case @disposition
        when 0
          succeed
        else
          fail(@disposition)
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
        opt :query, "", :type => :string
        opt :verbose
        opt :die, "", :short => "-e"
        opt :format, "", :type => :string, :default => "json"
        opt :timeout, "", :type => :int
        version ""
      end

      begin 
        options = parser.parse
        options[:action] = :get_tags if options.delete(:list)
        if options[:add]
          options[:action] = :add_tag
          options[:tag] = options.delete(:add)
        end
        if options[:remove]
          options[:action] = :remove_tag
          options[:tag] = options.delete(:remove)
        end
        if options[:query]
          options[:action] = :query_tags
          options[:tags] = parse_tag_list(options.delete(:query))
        end
        options[:format] = case options[:format]
                           when /^jso?n?$/, nil
                             :json
                           when /^ya?ml$/
                             :yaml
                           when /^te?xt$/, /^sh(ell)?/, 'list'
                             :text
                           else
                             raise Trollop::CommandlineError, "Unknown output format #{options[:format]}"
                           end
        options
      rescue Trollop::VersionNeeded
        write_output(version)
        succeed
      rescue Trollop::HelpNeeded
         write_output(Usage.scan(__FILE__))
         succeed
      rescue Trollop::CommandlineError => e
        write_error(e.message + "\nUse rs_tag --help for additional information")
        fail(1)
      rescue SystemExit => e
        raise e
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
    def send_command(cmd, verbose, timeout, &callback)
      config_options = ::RightScale::AgentConfig.agent_options('instance')
      listen_port = config_options[:listen_port]
      raise ::ArgumentError.new('Could not retrieve agent listen port') unless listen_port
      client = ::RightScale::CommandClient.new(listen_port, config_options[:cookie])
      timeout ||= TAG_REQUEST_TIMEOUT
      client.send_command(cmd, verbose, timeout, &callback)
      true
    end

    def serialize_operation_result(res)
      command_serializer = ::RightScale::Serializer.new
      ::RightScale::OperationResult.from_results(command_serializer.load(res))
    end

    # Splits the TAG_LIST parameter on space unless an equals is present in
    # order to support both the "x:y a:b" and the "x:y=a b c" (tag value
    # contains space(s)) cases. the "x:y=a b c:d=x y" case is ambiguous and will
    # be interpreted as follows:
    #   namespace=x, name=y, value=a b c:d=x y
    #
    # === Parameters
    # @param [String] tag_list to parse
    #
    # === Return
    # @return [Array] tags to query
    def parse_tag_list(tag_list)
      tag_list = tag_list.to_s
      if tag_list.index('=')
        [tag_list.strip]
      else
        tag_list.split
      end
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
    # === Options
    # :print_usage(Boolean):: Whether script usage should be printed, default to false
    #
    # === Return
    # R.I.P. does not return
    def fail(reason=nil, options={})
      case reason
      when TagError
        write_error(reason.message)
        code = reason.code
      when Errno::EACCES
        write_error(reason.message)
        write_error("Try elevating privilege (sudo/runas) before invoking this command.")
        code = 2
      when Exception
        write_error(reason.message)
        code = 50
      when String
        write_error(reason)
        code = 50
      when Integer
        code = reason
      else
        code = 1
      end

      write_output(Usage.scan(__FILE__)) if options[:print_usage]
      exit(code)
    end

    # Version information
    #
    # === Return
    # (String):: Version information
    def version
      gemspec = eval(File.read(File.join(File.dirname(__FILE__), '..', 'right_link.gemspec')))
      "rs_tag #{gemspec.version} - RightLink's tagger (c) 2009-2012 RightScale"
    end

  end # Tagger

end # RightScale

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
