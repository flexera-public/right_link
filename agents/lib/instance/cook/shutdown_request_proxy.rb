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

module RightScale

  # Proxy for a remote shutdown request state.
  class ShutdownRequestProxy

    include ShutdownRequestMixin

    # exceptions.
    class ShutdownQueryFailed < Exception; end

    # Class initializer.
    #
    # === Return
    # always true
    def self.init(command_client)
      @@command_client = command_client
      true
    end

    # Factory method
    #
    # === Return
    # (ShutdownRequestProxy):: the proxy instance for this class
    def self.instance
      # note that we never want the proxy to use a cached instance of the
      # shutdown state as RightScripts and command-line actions can change the
      # state without directly notifying the proxy.
      result = send_shutdown_request(:name => :get_shutdown_request)
      raise ShutdownQueryFailed.new("Unable to retrieve state of shutdown request from parent process.") unless result
      return result
    end

    # Submits a new shutdown request state which may be superceded by a
    # previous, higher-priority shutdown level.
    #
    # === Parameters
    # request[:level](String):: shutdown level
    # request[:immediately](Boolean):: shutdown immediacy or nil
    #
    # === Returns
    # result(ShutdownRequestProxy):: the updated shutdown request state
    def self.submit(request)
      level = request[:kind] || request[:level]
      immediately = !!request[:immediately]
      result = send_shutdown_request(:name => :set_shutdown_request, :level => level, :immediately => immediately)
      raise ShutdownQueryFailed.new("Unable to set state of shutdown request on parent process.") unless result
      return result
    end

    protected

    # Sends a get/set shutdown request using the command client.
    #
    # === Parameters
    # payload(Hash):: parameters to send
    #
    # === Return
    # result(ShutdownRequestProxy):: current shutdown request state or nil
    def self.send_shutdown_request(payload)
      # check initialization.
      raise NotInitialized.new("ShutdownRequestProxy.init has not been called") unless defined?(@@command_client)

      # use a queue to block and wait for response.
      result_queue = Queue.new
      @@command_client.send_command(payload) { |response| enqueue_result(result_queue, response) }
      result = result_queue.shift
      raise ShutdownQueryFailed.new("Unable to retrieve state of shutdown request from parent process.") unless result
      return result
    end

    # Pushes a valid shutdown request on the response queue or else nil for
    # synchronization purposes.
    #
    # === Parameters
    # result_queue(Queue):: queue for push
    # response(Hash):: response payload
    #
    # === Return
    # always true
    def self.enqueue_result(result_queue, response)
      result = nil
      begin
        if response[:error]
          RightLinkLog.error("Failed exchanging shutdown state: #{response[:error]}")
        else
          result = ShutdownRequestProxy.new
          result.level = response[:level]
          result.immediately! if response[:immediately]
        end
      rescue Exception => e
        RightLinkLog.error("Failed exchanging shutdown state - #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      end
      result_queue << result
      true
    end

  end  # ShutdownRequestProxy

end  # RightScale
