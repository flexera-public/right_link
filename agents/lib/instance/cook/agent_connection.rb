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

require 'singleton'

module RightScale

  # Wait up to 20 seconds before forcing disconnection to agent
  STOP_TIMEOUT = 20

  # Class managing connection to agent
  module AgentConnection

    # Set command client cookie and initialize responses parser
    def initialize(cookie, callback=nil)
      @cookie  = cookie
      @pending = 0
      @parser  = CommandParser.new do |data|
        if callback
          callback.call(data)
        else
          RightLinkLog.warn("[cook] Unexpected command protocol response '#{data}'") unless data == 'OK'
        end
        @pending -= 1
        on_stopped if @stopped_callback && @pending == 0
      end
    end

    # Send command to running agent
    #
    # === Parameters
    # options(Hash):: Hash of options and command name
    #   options[:name]:: Command name
    #   options[:...]:: Other command specific options, passed through to agent
    #
    # === Return
    # true:: Always return true
    def send_command(options)
      return if @stopped_callback
      @pending += 1
      command = options.dup
      command[:cookie] = @cookie
      send_data(CommandSerializer.dump(command))
      true
    end

    # Handle agent response
    #
    # === Return
    # true:: Always return true
    def receive_data(data)
      @parser.parse_chunk(data)
      true
    end

    # Stop command client, wait for all pending commands to finish prior
    # to calling given callback
    #
    # === Return
    # true:: Always return true
    #
    # === Block
    # called once all pending commands have completed
    def stop(&callback)
      send_command(:name => :close_connection)
      @stopped_callback = callback
      RightLinkLog.info("[cook] Disconnecting from agent (#{@pending} response#{@pending > 1 ? 's' : ''} pending)")
      @stop_timeout = EM::Timer.new(STOP_TIMEOUT) do
        RightLinkLog.warn("[cook] Time out waiting for responses from agent, forcing disconnection")
        @stop_timeout = nil
        on_stopped
      end
      true
    end

    # Called after all pending responses have been received
    #
    # === Return
    # true:: Always return true
    def on_stopped
      close_connection
      @stop_timeout.cancel if @stop_timeout
      @stopped_callback.call
    end

  end

end
