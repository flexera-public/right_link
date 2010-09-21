#
# Copyright (c) 2009 RightScale Inc
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
    def initialize(cookie)
      @cookie  = cookie
      @pending = 0
      @parser  = CommandParser.new do |data|
        RightLinkLog.warn("[cook] Invalid audit command response '#{data}'") unless data == 'OK'
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
      RightLinkLog.info("[cook] Disconnected from agent")
      @stopped_callback.call
    end

  end

  # Provides access to RightLink agent audit methods
  class AuditorStub

    include Singleton

    # Initialize command protocol, call prior to calling any instance method
    #
    # === Parameters
    # options[:listen_port]:: Command server listen port
    # options[:cookie]:: Command protocol cookie
    #
    # === Return
    # true:: Always return true
    def init(options)
      @agent_connection = EM.connect('127.0.0.1', options[:listen_port], AgentConnection, options[:cookie])
      true
    end

    # Stop command client, wait for all pending commands to finish prior
    # to calling given callback
    #
    # === Block
    # called once all pending commands have completed
    def stop(&callback)
      if @agent_connection
        # allow any pending audits to be sent prior to stopping agent connection
        # by placing stop on the end of the next_tick queue.
        EM.next_tick { @agent_connection.stop(&callback) }
      else
        callback.call
      end
    end

    # Update audit summary
    #
    # === Parameters
    # status(String):: New audit entry status
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def update_status(status, options={})
      send_command(:audit_update_status, status, options)
    end

    # Start new audit section
    #
    # === Parameters
    # title(String):: Title of new audit section, will replace audit status as well
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def create_new_section(title, options={})
      send_command(:audit_create_new_section, title, options)
    end

    # Append output to current audit section
    #
    # === Parameters
    # text(String):: Output to append to audit entry
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def append_output(text, options)
      send_command(:audit_append_output, text, options)
    end

    # Append info text to current audit section. A special marker will be prepended to each line of audit to
    # indicate that text is not some output. Text will be line-wrapped.
    #
    # === Parameters
    # text(String):: Informational text to append to audit entry
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def append_info(text, options={})
      send_command(:audit_append_info, text, options)
    end

    # Append error message to current audit section. A special marker will be prepended to each line of audit to
    # indicate that error message is not some output. Message will be line-wrapped.
    #
    # === Parameters
    # text(String):: Error text to append to audit entry
    # options[:audit_id](Integer):: Audit id
    #
    # === Return
    # true:: Always return true
    def append_error(text, options={})
      send_command(:audit_append_error, text, options)
    end

    protected

    # Helper method used to send command client request to RightLink agent
    #
    # === Parameters
    # cmd(String):: Command name
    # content(String):: Audit content
    # options(Hash):: Audit options
    #
    # === Return
    # true:: Always return true
    def send_command(cmd, content, options={})
      options ||= {}
      begin
        cmd = { :name => cmd, :content => content, :options => options }
        EM.next_tick { @agent_connection.send_command(cmd) }
      rescue Exception => e
        $stderr.puts 'Failed to audit'
        $stderr.puts "Failed to audit (#{cmd[:name]}) - #{e.message} from\n#{e.backtrace.join("\n")}"
      end
    end

  end

end
