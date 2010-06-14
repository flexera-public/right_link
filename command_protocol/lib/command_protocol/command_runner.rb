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

    # Command runner listens to commands and deserializes them using YAML
    # Each command is expected to be a hash containing the :name and :options keys
    #
    # === Parameters
    # socket_port(Integer):: Socket port on which to listen for connection
    # commands(Hash):: Commands exposed by agent
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # (RightScale::Exceptions::Application):: If +start+ has already been called and +stop+ hasn't since
    # (RightScale::Exceptions::IO):: If named pipe creation failed
    def self.start(socket_port, commands)
      CommandIO.instance.listen(socket_port) do |c, conn|
        begin
          cmd_name = c[:name].to_sym
          if commands.include?(cmd_name)
            commands[cmd_name].call(c, conn)
          else
            RightLinkLog.info("Unknown command '#{cmd_name}'")
          end
        rescue Exception => e
          RightLinkLog.info("Command failed (#{e.message}) '#{c.inspect}'")
        end
      end
      true
    end

    # Stop command runner, cleanup all opened file descriptors and delete pipe
    #
    # === Return
    # true:: If command listener was listening
    # false:: Otherwise
    def self.stop
      CommandIO.instance.stop_listening
    end

  end

end
