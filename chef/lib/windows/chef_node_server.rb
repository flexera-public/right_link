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
require 'singleton'

module RightScale

  module Windows

    # Provides a server for a named pipe connection which serves data from a
    # node structure organized as a hierarchy of hashes to privitives, arrays
    # and subhashes. complex types can also appear but will be served out as
    # hashes without type. caution should be used not to use complex types which
    # have circular references.
    class ChefNodeServer

      include Singleton

      CHEF_NODE_PIPE_NAME = 'chef_node_D1D6B540-5125-4c00-8ABF-412417774DD5'
      COMMAND_KEY = "Command"
      PATH_KEY = "Path"
      NODE_VALUE_KEY = "NodeValue"

      attr_reader   :node
      attr_accessor :current_resource
      attr_accessor :new_resource

      # Starts the pipe server by creating an asynchronous named pipe. Returns
      # control to the caller after adding the pipe to the event machine.
      #
      # === Parameters
      # options[:node](Node):: Chef node, required
      #
      # === Return
      # true:: If server was successfully started
      # false:: Otherwise
      def start(options)
        return true if @pipe_eventable # Idempotent

        RightLinkLog.debug("[ChefNodeServer] - Starting")
        @node = options[:node] || {}
        @pipe_eventable = nil
        @current_resource = nil
        @new_resource = nil

        flags = ::Win32::Pipe::ACCESS_DUPLEX | ::Win32::Pipe::OVERLAPPED
        pipe  = PipeServer.new(CHEF_NODE_PIPE_NAME, 0, flags)
        res   = true
        begin
          options = {:target          => self,
                     :request_handler => :request_handler,
                     :pipe            => pipe}
          @pipe_eventable = EM.watch(pipe, PipeServerHandler, options)
          @pipe_eventable.notify_readable = true
        rescue Exception => e
          pipe.close rescue nil
          res = false
        end
        RightLinkLog.debug("[ChefNodeServer] - Started = #{res}")
        res
      end

      # Stops the pipe server by detaching the eventable from the event machine.
      #
      # === Return
      # true:: Always return true
      def stop
        RightLinkLog.debug("[ChefNodeServer] - Stopping - need to stop = #{!@pipe_eventable.nil?}")
        @pipe_eventable.force_detach if @pipe_eventable
        @pipe_eventable = nil
        true
      end

      # Handler for data node requests. Expects complete requests and responses
      # to appear serialized as JSON on individual lines (i.e. delimited by
      # newlines). note that JSON text escapes newline characters within string
      # values and normally only includes whitespace for human-readability.
      def request_handler(request_data)
        # assume request_data is a single line with a possible newline trailing.
        request = JSON.load(request_data.chomp)
        if request.has_key?(COMMAND_KEY)
          handler = REQUEST_HANDLERS[request[COMMAND_KEY]]
          RightLinkLog.debug("handler = #{handler}")
          return self.send(handler, request) if handler
        end
        raise "Invalid request"
      rescue Exception => e
        return JSON.dump( { :Error => "#{e.class}: #{e.message}", :Detail => e.backtrace.join("\n") } ) + "\n"
      end

      private

      REQUEST_HANDLERS = {"GetChefNodeRequest"        => :handle_get_chef_node_request,
                          "SetChefNodeRequest"        => :handle_set_chef_node_request,
                          "GetCurrentResourceRequest" => :handle_get_current_resource_request,
                          "SetCurrentResourceRequest" => :handle_set_current_resource_request,
                          "GetNewResourceRequest"     => :handle_get_new_resource_request,
                          "SetNewResourceRequest"     => :handle_set_new_resource_request }

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

      # Handles a Get-ChefNode request by finding the node matching the path,
      # normalizing and then JSONing the data out.
      #
      # === Parameters
      # request(Hash):: hash containing the following parameters:
      #
      # PATH_KEY(Array):: array of path elements
      #
      # === Returns
      # response(String):: JSON structure containing found value or error
      def handle_get_chef_node_request(request)
        return handle_get_from_hash_request(request, @node)
      end

      # Handles a Set-ChefNode request by attempting to build the hash hierarchy
      # to the requested path depth and the inserting the given value.
      #
      # === Parameters
      # request(Hash):: hash containing the following parameters:
      #
      # PATH_KEY(Array):: array of path elements
      #
      # NODE_VALUE_KEY(Object):: node value to set
      #
      # === Returns
      # response(String):: JSON structure containing acknowledgement or error
      def handle_set_chef_node_request(request)
        handle_set_into_hash_request(request, @node)
      end

      # Handles a Get-CurrentResource request.
      #
      # === Parameters
      # request(Hash):: hash containing the following parameters:
      #
      # === Returns
      # response(String):: JSON structure containing current resource or error
      def handle_get_current_resource_request(request)
        return handle_get_resource_request(request, @current_resource)
      end

      # Handles a Set-CurrentResource request.
      #
      # === Parameters
      # request(Hash):: hash containing the following parameters:
      #
      # === Returns
      # response(String):: empty JSON structure or error.
      def handle_set_current_resource_request(request)
        return handle_set_resource_request(request, @current_resource)
      end

      # Handles a Get-NewResource request.
      #
      # === Parameters
      # request(Hash):: hash containing the following parameters:
      #
      # PATH_KEY(Array):: array of path elements
      #
      # === Returns
      # response(String):: JSON structure containing new resource or error
      def handle_get_new_resource_request(request)
        handle_get_resource_request(request, @new_resource)
      end

      # Handles a Set-NewResource request.
      #
      # === Parameters
      # request(Hash):: hash containing no additional parameters.
      #
      # PATH_KEY(Array):: array of path elements
      #
      # NODE_VALUE_KEY(Object):: node value to set
      #
      # === Returns
      # response(String):: empty JSON structure or error.
      def handle_set_new_resource_request(request)
        return handle_set_resource_request(request, @new_resource)
      end

      # Handles a get from hash request by normalizing and then JSONing
      # the current resource, if any.
      #
      # === Parameters
      # request(Hash):: hash containing no additional parameters.
      #
      # hash(Hash):: a hash or hash-like object containing data to query.
      #
      # === Returns
      # response(String):: JSON structure containing current resource or error
      def handle_get_from_hash_request(request, hash)
        raise "Missing required Path parameter" unless path = request[PATH_KEY]
        node_value = get_node_value_from_hash(path, hash) rescue nil
        node_value = normalize_node_value(node_value)
        return JSON.dump( { :Path => path, :NodeValue => node_value } )
      end

      # Handles a set into hash request.
      #
      # === Parameters
      # request(Hash):: hash containing no additional parameters.
      #
      # hash(Hash):: a hash or hash-like object containing data to query.
      #
      # === Returns
      # response(String):: JSON structure containing current resource or error
      def handle_set_into_hash_request(request, hash)
        raise "Missing required Path parameter" unless path = request[PATH_KEY]
        raise "Missing required NodeValue parameter" unless request.has_key?(NODE_VALUE_KEY)  # value can be nil
        node_value = request[NODE_VALUE_KEY]
        set_node_value_into_hash(path, hash, node_value)
        return JSON.dump( { :Path => path } )
      end

      # Handles a get resource request by normalizing and then JSONing
      # the current resource, if any.
      #
      # === Parameters
      # request(Hash):: hash containing no additional parameters.
      #
      # resource(Object):: resource for response.
      #
      # === Returns
      # response(String):: JSON structure containing current resource or error
      def handle_get_resource_request(request, resource)
        # note that Chef::Resource and subclasses support :to_hash which will
        # give us the interesting instance variables.
        if resource && resource.respond_to?(:to_hash)
          resource = resource.to_hash
          resource = Mash.new(resource) unless resource.kind_of?(Mash)
        end
        return handle_get_from_hash_request(request, resource)
      end

      # Handles a set resource request by attempting to set member variables or
      # set hash pairs depending on type.
      #
      # === Parameters
      # request(Hash):: hash containing the following parameters:
      #
      # resource(Object):: resource object to modify by request.
      #
      # === Returns
      # response(String):: JSON structure containing acknowledgement or error
      def handle_set_resource_request(request, resource)
        # resource may or may not support hash insertion, but we can reuse the
        # generic code which parses parameters and inserts into a new hash.
        hash = {}
        result = handle_set_into_hash_request(request, hash)

        # note that Chef::Resource and subclasses support :to_hash no :from_hash
        # and so have to set instance variables by mutator. we also want to
        # support hash types which will likely support both :has_key? and
        # :to_hash so check for :has_key? first.
        if resource.respond_to?(:has_key?)
          hash.each do |key, value|
            # note it is non-trivial here to determine if keys are supposed to
            # be tokens or strings, so always use Mash-like objects for such
            # resources.
            resource[key] = value
          end
        elsif resource.respond_to?(:to_hash)
          # set any instance variables by public mutator (which may fail due
          # to validation, etc.).
          hash.each do |key, value|
            # Chef resources normally implement validating accessor/mutator
            # single methods which take either nil for get or the value to
            # set, but also check the name= method for completeness.
            name_equals_sym = (key + "=").to_sym
            if resource.respond_to?(name_equals_sym)
              RightLinkLog.debug("calling resource.#{name_equals_sym} #{value.inspect[0,64]}") if RightLinkLog.debug?
              resource.send(name_equals_sym, value)
            else
              RightLinkLog.debug("calling resource.#{key} #{value.inspect[0,64]}") if RightLinkLog.debug?

              resource.send(key.to_sym, value)
            end
          end
        else
          raise "Resource of type #{resource.class} cannot be modified."
        end

        return result
      end

      # Queries the node value given by path from the node for this server.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      #
      # hash(Hash):: hash or hash-like object to query.
      #
      # === Returns
      # node_value(Object):: node value from path or nil
      def get_node_value_from_hash(path, hash)
        # special case for the empty path element
        return hash if (1 == path.length && path[0].to_s.length == 0)

        node_by_path = node_by_path_statement(path)
        result = instance_eval node_by_path
        RightLinkLog.debug("#{node_by_path} = #{result.inspect[0,64]}") if RightLinkLog.debug?
        return result
      end

      # Inserts the node value given by path into the node for this server,
      # replacing any existing value.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      #
      # hash(Hash):: hash or hash-like object to query.
      #
      # node_value(Object):: value to insert.
      #
      # === Return
      # true:: Always return true
      def set_node_value_into_hash(path, hash, node_value)
        # build up hash structure incrementally to avoid forcing the caller to
        # explicitly insert all of the hashes described by the path.
        raise InvalidPathException, "Cannot set the root node" if (path.empty? || path[0].empty?)
        parent_path = []
        path[0..-2].each do |element|
          raise InvalidPathException, "At least one path element was empty" if element.empty?
          parent_path << element
          parent_node = get_node_value_from_hash(parent_path, hash)
          if parent_node.nil? || false == parent_node.respond_to?(:has_key?)
            node_by_path = node_by_path_statement(parent_path)
            instance_eval "#{node_by_path} = {}"
          end
        end

        # insert node value.
        node_by_path = node_by_path_statement(path)
        instance_eval "#{node_by_path} = node_value"

        true
      end

      # Generates an evaluatable statement for querying Chef node by path.
      #
      # === Parameters
      # path(Array):: array containing path elements.
      def node_by_path_statement(path)
        return "hash[\"#{path.join('"]["')}\"]"
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
        normalize_node_value3(node_value, [], Set.new)
      end

      # Recursively normalizes the given node value to produce simple
      # containers, hashes and primitives for JSON serialization. Also detects
      # circular references.
      #
      # === Parameters
      # node_value(Object):: value to normalize
      #
      # depth(Array):: current depth of hash keys or empty
      #
      # node_value_set(Set):: set used for circular reference detection.
      #
      # === Returns
      # normal_value(Object):: normalized value
      def normalize_node_value3(node_value, depth, node_value_set)
        return nil if node_value.nil?
        case node_value
        when FalseClass, TrueClass, Numeric, String
          # primitives can appear repeatedly but are not a circular reference.
          return node_value
        when Array
          # arrays can contain circular references.
          if node_value_set.add?(node_value.object_id)
            result = []
            node_value.each { |array_value| result << normalize_node_value3(array_value, depth, node_value_set) }
            return result
          else
            raise CircularReferenceException, "Circular reference detected at depth = #{depth.join(', ')}"
          end
        when Chef::Node
          # the Chef root node is a special case because we don't want to return
          # the entire node in a JSON stream. only return the root keys.
          result = []
          node_value.each { |key, value| result << key.to_s }
          return result
        else
          # note that the root node (i.e. Chef::Node) does not respond to
          # has_key? but otherwise behaves like a hash.
          if node_value.respond_to?(:has_key?) || node_value.kind_of?(Chef::Node)
            # hashes can contain circular references.
            if node_value_set.add?(node_value.object_id)
              result = {}
              node_value.each do |key, value|
                depth.push key
                begin
                  # recursion.
                  result[key.to_s] = normalize_node_value3(value, depth, node_value_set)
                ensure
                  depth.pop
                end
              end
              return result
            else
              RightLinkLog.debug("Handling circular reference for hash by responding with key set at depth = #{depth.join(', ')}")
              result = []
              node_value.each { |key, value| result << key.to_s }
              return result
            end
          else
            # currently ignoring complex types except for converting them to
            # string value.
            return node_value.to_s
          end
        end
      end
    end

  end

end
