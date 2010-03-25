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
require File.expand_path(File.join(File.dirname(__FILE__), 'pipe_server'))
require 'json'

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
      # node(Hash):: data node or empty (default)
      # verbose(Boolean):: true if printing verbose output, false to be silent (default)
      def initialize(options = {})
        @node = options[:node] || {}
        @verbose = options[:verbose] || false
      end

      # Starts the pipe server by creating an asynchronous named pipe. Returns
      # control to the caller after adding the pipe to the event machine.
      def start
        flags = ::Win32::Pipe::ACCESS_DUPLEX | ::Win32::Pipe::OVERLAPPED
        pipe = PipeServer.new(CHEF_NODE_PIPE_NAME, 0, flags)
        @pipe_eventable = EM.attach(pipe, PipeServerHandler, self, :request_handler, pipe, @verbose)
      end

      # Stops the pipe server by detaching the eventable from the event machine.
      def stop
        @pipe_eventable.force_detach
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
            elsif 2 == request.keys.size && request[PATH_KEY] && request[NODE_VALUE_KEY]
              return handle_set_chef_node_request(request[PATH_KEY], request[NODE_VALUE_KEY])
            else
              raise "Invalid request"
            end
          end
        end
        return nil
      rescue Exception => e
        return JSON.dump( { :Error => e.message, :Detail => e.backtrace.join("\n") } ) + "\n"
      end

      private

      def handle_get_chef_node_request(path)
        node_value = get_node_value(path) rescue nil
        return JSON.dump( { :Path => path, :NodeValue => node_value } ) + "\n"
      end

      def handle_set_chef_node_request(path, node_value)
        set_node_value(path, node_value)
        return JSON.dump( { :Path => path } ) + "\n"
      end

      # Queries the node value given by path from the node for this server.
      #
      # === Parameters
      # path(Array):: array containing at path elements.
      #
      # === Returns
      # node_value(Object):: node value from path or nil
      def get_node_value(path)
        # special case for the empty path element
        return @node if (1 == path.length && path[0].to_s.length == 0)

        # iterate path looking for each node matching element as either a string
        # or symbol key.
        current_node = @node
        path.each do |element|
          if is_hash?(current_node)
            element = element.to_s
            if current_node[element]
              current_node = current_node[element]
            elsif current_node[element.to_sym]
              current_node = current_node[element.to_sym]
            else
              return nil
            end
          else
            return nil
          end
        end
        return current_node
      end

      # Inserts the node value given by path into the node for this server,
      # replacing any existing value.
      #
      # === Parameters
      # path(Array):: array containing at path elements.
      # node_value(Object):: value to insert.
      def set_node_value(path, node_value)
        current_node = @node
        index = 0
        path.each do |element|
          # note that setting the root of the node is not supported even though
          # get is supported. also don't support setting children using the
          # empty key.
          element = element.to_s
          if 0 == element.length
            raise "Path contains at least one empty element."
          end
          if current_node[element.to_sym]
            element = element.to_sym
          end
          if index + 1 == path.size
            # note that Chef may ignore setting the node value if the node has
            # been flagged to only set the value once.
            current_node[element] = node_value
          elsif is_hash?(current_node) && current_node[element]
            current_node = current_node[element]
          else
            current_node[element] = {}
            current_node = current_node[element]
          end
          index += 1
        end
      end

      # Determines if the given object supports a hash interface. Note that the
      # o.responds_to?(:[]) test produces a false positive because strings and
      # integers both respond to [].
      #
      # === Parameters
      # o(Object):: object to test
      #
      # === Returns
      # hashable(Boolean):: true if object is hashable
      def is_hash? o
        return true if o.kind_of?(Hash)
        return true if o.kind_of?(Chef::Node)
        return o.kind_of?(Chef::Node::Attribute)
      end

    end

  end

end
