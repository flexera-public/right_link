#
# Copyright (c) 2010 RightScale Inc
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
require File.normalize_path(File.join(File.dirname(__FILE__), 'pipe_server'))
require 'json'
require 'set'

module RightScale

  module Windows

    # Provides a server for a named pipe connection which serves data from a
    # node structure organized as a hierarchy of hashes to privitives, arrays
    # and subhashes. complex types can also appear but will be served out as
    # hashes without type. caution should be used not to use complex types which
    # have circular references.
    class ChefNodeServer

      CHEF_NODE_PIPE_NAME = 'chef_node_D1D6B540-5125-4c00-8ABF-412417774DD5'
      PATH_KEY = "Path"
      NODE_VALUE_KEY = "NodeValue"

      attr_reader :node
      attr_accessor :verbose

      # === Parameters
      # options(Hash):: hash of options including the following
      #
      # node(Hash):: data node or empty (default)
      #
      # logger(Logger):: logger or nil
      def initialize(options = {})
        @node = options[:node] || {}
        @logger = options[:logger]
        @pipe_eventable = nil
      end

      # Starts the pipe server by creating an asynchronous named pipe. Returns
      # control to the caller after adding the pipe to the event machine.
      def start
        flags = ::Win32::Pipe::ACCESS_DUPLEX | ::Win32::Pipe::OVERLAPPED
        pipe = PipeServer.new(CHEF_NODE_PIPE_NAME, 0, flags)
        begin
          options = {:target => self,
                     :request_handler => :request_handler,
                     :pipe => pipe,
                     :logger => @logger}
          @pipe_eventable = EM.attach(pipe, PipeServerHandler, options)
        rescue
          pipe.close rescue nil
          raise
        end
      end

      # Stops the pipe server by detaching the eventable from the event machine.
      def stop
        @pipe_eventable.force_detach if @pipe_eventable
        @pipe_eventable = nil
      end

      # Handler for data node requests. Expects complete requests and responses
      # to appear serialized as JSON on individual lines (i.e. delimited by
      # newlines). note that JSON text escapes newline characters within string
      # values and normally only includes whitespace for human-readability.
      def request_handler(data)
        # parse request linewise.
        io = StringIO.new(data)
        while (line = io.gets) do
          if line.chomp.length > 0
            request = JSON.load(line) rescue {}
            if 1 == request.keys.size && request[PATH_KEY]
              return handle_get_chef_node_request(request[PATH_KEY])
            elsif 2 == request.keys.size && request[PATH_KEY] && request.has_key?(NODE_VALUE_KEY)
              return handle_set_chef_node_request(request[PATH_KEY], request[NODE_VALUE_KEY])
            else
              raise "Invalid request"
            end
          end
        end
        return nil
      rescue Exception => e
        return JSON.dump( { :Error => "#{e.class}: #{e.message}", :Detail => e.backtrace.join("\n") } ) + "\n"
      end

      private

      # exception for a circular reference in node structure.
      class CircularReferenceException < StandardError
        def initialize(message)
          super(message)
        end
      end

      # exception for an invalid path.
      class InvalidPathException < StandardError
        def initialize(message)
          super(message)
        end
      end

      # Handles a get-ChefNode request by finding the node matching the path,
      # normalizing and then JSONing the data out.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      #
      # === Returns
      # response(String):: JSON structure containing found value or error
      def handle_get_chef_node_request(path)
        node_value = get_node_value(path) rescue nil
        node_value = normalize_node_value(node_value)
        begin
          return JSON.dump( { :Path => path, :NodeValue => node_value } ) + "\n"
        rescue JSON::GeneratorError
          # attempt to return keys in case a hash contains some values which
          # cause JSON to fail. it is possible that the keys cause the failure.
          if node_value.kind_of? Hash
            return JSON.dump( { :Path => path, :NodeValue => node_value.keys } ) + "\n"
          else
            if @verbose
              string_value = node_value.to_s
              puts "JSON rejected value: #{string_value}"
            end
            raise
          end
        end
      end

      # Handles a set-ChefNode request by attempting to build the hash hierarchy
      # to the requested path depth and the inserting the given value.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      #
      # node_value(Object):: value to insert
      #
      # === Returns
      # response(String):: JSON structure containing acknowledgement or error
      def handle_set_chef_node_request(path, node_value)
        set_node_value(path, node_value)
        return JSON.dump( { :Path => path } ) + "\n"
      end

      # Queries the node value given by path from the node for this server.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      #
      # === Returns
      # node_value(Object):: node value from path or nil
      def get_node_value(path)
        # special case for the empty path element
        return @node if (1 == path.length && path[0].to_s.length == 0)

        node_by_path = node_by_path_statement(path)
        instance_eval node_by_path
      end

      # Inserts the node value given by path into the node for this server,
      # replacing any existing value.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      #
      # node_value(Object):: value to insert.
      def set_node_value(path, node_value)
        # build up hash structure incrementally to avoid forcing the caller to
        # explicitly insert all of the hashes described by the path.
        raise InvalidPathException, "Cannot set the root node" if (path.empty? || path[0].empty?)
        parent_path = []
        path[0..-2].each do |element|
          raise InvalidPathException, "At least one path element was empty" if element.empty?
          parent_path << element
          parent_node = get_node_value(parent_path)
          if parent_node.nil? || false == parent_node.respond_to?(:has_key?)
            node_by_path = node_by_path_statement(parent_path)
            instance_eval "#{node_by_path} = {}"
          end
        end

        # insert node value.
        node_by_path = node_by_path_statement(path)
        instance_eval "#{node_by_path} = node_value"
      end

      # Generates an evaluatable statement for querying Chef node by path.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      def node_by_path_statement(path)
        return "@node[\"#{path.join('"]["')}\"]"
      end

      # Nnormalizes the given node value to produce simple containers, hashes
      # and primitives for JSON serialization. Also detects circular references.
      #
      # === Parameters
      # node_value(Object):: value to normalize
      #
      # node_value_set(Set):: set used for circular reference detection.
      #
      # === Returns
      # normal_value(Object):: normalized value
      def normalize_node_value(node_value)
        normalize_node_value2(node_value, Set.new)
      rescue CircularReferenceException
        # primitives don't have circular references, arrays are undisplayable if
        # they contain a circular reference.
        raise if node_value.kind_of?(Array)

        # node must be a hash at this point so return a flat array of keys for
        # information purposes. this at least gives the user some clue as to why
        # the full data cannot be sent.
        puts "handling circular reference by responding with key set" if @verbose
        result = []
        node_value.each { |key, value| result << key.to_s }
        return result
      end

      # Recursively normalizes the given node value to produce simple
      # containers, hashes and primitives for JSON serialization. Also detects
      # circular references.
      #
      # === Parameters
      # node_value(Object):: value to normalize
      #
      # node_value_set(Set):: set used for circular reference detection.
      #
      # === Returns
      # normal_value(Object):: normalized value
      def normalize_node_value2(node_value, node_value_set)
        return nil if node_value.nil?
        if node_value_set.add?(node_value.object_id)
          case node_value
          when FalseClass, TrueClass, Numeric, String
            return node_value
          when Array
            result = []
            node_value.each { |array_value| result << normalize_node_value2(array_value, node_value_set) }
            return result
          else
            # note that the root node (i.e. Chef::Node) does not respond to
            # has_key? but otherwise behaves like a hash.
            if node_value.respond_to?(:has_key?) || node_value.kind_of?(Chef::Node)
              result = {}
              node_value.each { |key, value| result[key.to_s] = normalize_node_value2(value, node_value_set) }
              return result
            else
              return node_value.to_s
            end
          end
        else
          raise CircularReferenceException, "Circular reference detected at depth >= #{node_value_set.size}"
        end
      end

    end

  end

end
