#
# Copyright (c) 2009-2011 RightScale Inc
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

require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'instance', 'instance_commands'))

# Monkey patch RightScale::InstanceCommands to add test commands
module RightScale

  class InstanceCommands

    COMMANDS[:test_reliability] = 'Send messages to core agent as part of reliability test'

    # Repeatedly send a test command to core agent tester
    #
    # === Parameters
    # opts(Hash):: Options:
    #   :conn(EM::Connection):: Connection used to send reply
    #   :options(Hash):: Test command payload and options:
    #     :test(String):: Test name
    #     :type(Symbol):: :send_push, :send_persistent_push, :send_retryable_request, or :send_persistent_request
    #     :index(Integer):: Starting index for iteration, defaults to 0
    #     :times(Integer):: Number of times to send message
    #     :exit(Integer):: Index at which core agent is to exit, if at all
    #     :kill(Integer):: Id of process to be killed, if any
    #
    # === Return
    # true:: Always return true
    def test_reliability_command(opts)
      options = opts[:options].dup
      options[:agent_identity] = @agent_identity
      options[:index] ||= 0
      exit_index = options[:exit]
      failure = 0

      options[:times].times do
        begin
          options[:exit] = (options[:index] == exit_index)
          Log.info("Sending test #{options[:test]} request, " +
                   "index = #{options[:index]}, " +
                   "exit = #{options[:exit].inspect}, " +
                   "kill = #{options[:kill].inspect}")
          Sender.instance.__send__(options[:type], "/tester/test_reliability", options.dup, options[:target]) do |res|
            res = RightScale::OperationResult.from_results(res)
            if res.success?
              Log.info("Received test #{options[:test]} response, index = #{res.content}")
            elsif res.error?
              Log.info("Received test #{options[:test]} response, error = \"#{res.content}\"")
            else
              Log.info("Received test #{options[:test]} response, unexpected = \"#{res.content}\", " +
                       "status = #{res.status_code}")
            end
          end
        rescue Exception => e
          Log.error("Received test #{options[:test]} failed: #{e.message}")
          failure += 1
        end
        options[:index] += 1
      end
      failures = " with #{failure} send failures" if failure > 0
      CommandIO.instance.reply(opts[:conn], "Finished sending test #{options[:times]} #{options[:test]} requests#{failures}")
    end

  end # InstanceCommands

end # RightScale

class Tester

  include RightScale::Actor

  expose :test_reliability

  # Receive test_reliability command and perform requested actions
  # Result is returned but this may be a push rather than a request
  #
  # === Options
  # :test(String):: Test name
  # :index(Integer):: Message index
  # :exit(Boolean):: Whether to exit process
  # :kill(Integer):: Id of process to kill
  #
  # === Return
  # (OperationResult):: SUCCESS result containing index if successful,
  #   otherwise ERROR with message
  def test_reliability(options)
    options = RightScale::SerializationHelper.symbolize_keys(options)
    RightScale::Log.info("Received test #{options[:test]} request, " +
                         "index = #{options[:index]}, " +
                         "exit = #{options[:exit].inspect}, " +
                         "kill = #{options[:kill].inspect}")
    if options[:kill]
      begin
        Process.kill('KILL', options[:kill])
      rescue Exception => e
        return RightScale::OperationResult.error("Kill failed: #{e.message}")
      end
    end
    Process.exit! if options[:exit]
    RightScale::OperationResult.success(options[:index])
  end

end # Tester

