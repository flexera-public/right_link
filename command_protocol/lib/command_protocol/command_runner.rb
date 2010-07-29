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

module RightScale

  # Run commands exposed by an agent
  # External processes can send commands through a socket with the specified port
  class CommandRunner

    class << self
      # (Integer) Port command runner is listening on
      attr_reader :listen_port

      # (String) Cookie used by command protocol
      attr_reader :cookie
    end

    # Command runner listens to commands and deserializes them using YAML
    # Each command is expected to be a hash containing the :name and :options keys
    #
    # === Parameters
    # socket_port(Integer):: Base socket port on which to listen for connection,
    #                        increment and retry if port already taken
    # identity(String):: Agent identity
    # commands(Hash):: Commands exposed by agent
    # options(Hash):: Optional, options used to retrieve agent pid file
    #                 If present pid file will get updated with listen port
    #
    # === Return
    # cmd_options[:cookie](String):: Command protocol cookie
    # cmd_options[:listen_port](Integer):: Command server listen port
    #
    # === Raise
    # (RightScale::Exceptions::Application):: If +start+ has already been called and +stop+ hasn't since
    def self.start(socket_port, identity, commands, options=nil)
      cmd_options = nil
      @listen_port = socket_port
      begin
        CommandIO.instance.listen(socket_port) do |c, conn|
          begin
            cmd_cookie = c[:cookie]
            if cmd_cookie == @cookie
              cmd_name = c[:name].to_sym
              if commands.include?(cmd_name)
                commands[cmd_name].call(c, conn)
              else
                RightLinkLog.warn("Unknown command '#{cmd_name}', known commands: #{commands.keys.join(', ')}")
              end
            else
              RightLinkLog.error("Invalid cookie used by command protocol client (#{cmd_cookie})")
            end
          rescue Exception => e
            RightLinkLog.warn("Command failed (#{e.message}) at\n#{e.backtrace.join("\n")}")
          end
        end

        @cookie = AgentIdentity.generate
        cmd_options = { :listen_port => @listen_port, :cookie => @cookie }
        # Now update pid file with command port and cookie
        if options
          pid_file = PidFile.new(identity, options)
          if pid_file.exists?
            pid_file.set_command_options(cmd_options)
          else
            RightLinkLog.warn("Failed to update listen port in PID file - no pid file found for agent with identity #{identity}")
          end
        end

        RightLinkLog.info("[setup] Command server started listening on port #{@listen_port}")
      rescue Exceptions::IO
        # Port already taken, increment and retry
        cmd_options = start(socket_port + 1, identity, commands, options)
      end

      cmd_options
    end

    # Stop command runner, cleanup all opened file descriptors and delete pipe
    #
    # === Return
    # true:: If command listener was listening
    # false:: Otherwise
    def self.stop
      CommandIO.instance.stop_listening
      RightLinkLog.info("[stop] Command server stopped listening")
    end

  end

end
