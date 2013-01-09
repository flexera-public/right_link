# === Synopsis:
#   RightScale Agent Watcher
#
#   Agent monitoring intelligence. Will watch a given list of agents for
#   unexpected termination and react accordingly. This can be either simply
#   logging to a given IO stream, restarting the agent or yielding to any
#   arbitrary block passed in during initialization.
#
# Copyright (c) 2013 RightScale Inc
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
#

require 'rubygems'
require 'right_agent/pid_file'
require 'thread'

module RightScale 

  class AgentWatcher
    class AgentRunning < Exception; end
    class AgentStopped < Exception; end
    class AlreadyWatched < Exception; end
    class UnknownAgent < Exception; end

    DEFAULT_FREQUENCY_CHECK = 5

    def initialize(logger, pid_dir=nil)
      @logger = logger
      @pid_dir = pid_dir
      @running = false
      @stopped_list = {}
      @watched_list = {}
      @watch_list_lock = Mutex.new
      @watch_list_signal = ConditionVariable.new
    end

    def log_info(s)
      @logger.call(s)
    end

    def kill_agent(identity, signal='SIGKILL')
      @watch_list_lock.synchronize do
        raise UnknownAgent("#{id} is not a known agent.") unless @watched_list.has_key?
        raise AgentStopped unless agent_running?(identity)
        Process.kill(signal, @watched_list[identity][:pid].read_pid[:pid])
      end
    end

    def restart_agent(identity)
      stop_agent(identity)
      start_agent(identity)
    end

    def start_watching()
      # This logic is implemented with a priority queue of "next check" times:
      #
      # This allows us not to have to start a bunch of timers and do time
      # alrithmatic which can be tricky when someone goes and changes the date
      # on the system this code is running.

      # Initialize all agents
      @watch_list_lock.synchronize {
        @watched_list.each { |k, v| v[:next_check] = v[:freq] }
      }

      log_info("Starting the AgentWatcher.")
      @thread ||= Thread.new do
        @running = true
        while @running
          next_check = 0
          time_start = Time.now

          # TODO: This may need to be refactored into a real priority queue if we
          # start to have large amounts of agents assigned, rather than incur the
          # overhead of discovering the next smallest number every iteration. -brs
          @watch_list_lock.synchronize do
            # No use doing anything till we have something to work on
            @watch_list_signal.wait(@watch_list_lock) until @watched_list.size > 0 or not @running

            # Check all processes in the list with a next check time of zero
            # replacing the next check time with their frequency.
            @watched_list.each do |k,v|
              if v[:next_check] <= 0
                v[:next_check] = v[:freq]
                check_agent(k)
              end
            end

            # Find the lowest next check
            @watched_list.each do |k,v|
              next_check = v[:next_check] unless (next_check > 0 and next_check < v[:next_check])
            end

            # Subtract this from all the elements before we sleep
            @watched_list.each do |k,v| 
              v[:next_check] -= next_check
            end
          end

          # Account for the time it took to check agents and find the next
          # check time.
          next_check -= (Time.now - time_start).to_i

          # Sleep for the next check time
          next_check -= sleep(next_check) while (next_check > 0 and @running)
        end
      end
    end

    def start_agent(identity)
      @watch_list_lock.synchronize {
        raise UnknownAgent("#{id} is not a known stopped agent.") unless @stopped_list.has_key?
        raise AgentRunning if agent_running?(identity)
        agent = @stopped_list.delete(identity)
        agent[:pid].remove
        if system("#{agent[:exec]} --start")
          log_info("Successfully started the #{identity} agent.")
          agent[:next_check] = agent[:freq]
          @watched_list[identity] = agent
        else
          @stopped_list[identity] = agent
        end
      }
    end

    def stop_watching()
      return unless @running
      log_info("Stopping the AgentWatcher.")
      @running = false
      @watch_list_signal.signal
      @thread.join
      @thread = nil
      log_info("AgentWatcher Stopped.")
    end

    def stop_agent(identity)
      @watch_list_lock.synchronize {
        raise UnknownAgent("#{id} is not a known agent.") unless @watched_list.has_key?
        raise AgentStopped if agent_running?(identity)
        agent = @watched_list.delete(identity)
        if system("#{agent[:exec]} --stop")
          log_info("Successfully stopped the #{identity} agent.")
          agent[:pid].remove
        end
        @stopped_list[identity] = agent
      }
    end

    def watch_agent(identity, exec, freq=DEFAULT_FREQUENCY_CHECK)
      # Make things simple for now and require a resolution of 1 second
      # for the frequency check.
      raise BadFrequency unless (freq > 1)

      # Protect the watch list from the thread monitoring the agents
      @watch_list_lock.synchronize {
        unless @watched_list.has_key?(identity)
          # If we were given a block, use that for state change, otherwise
          # we'll just use the logging facility of our self
          action = (block_given? && Proc.new) || Proc.new do |id, state, mesg|
            log_info("#{id} has changed to [#{state.to_s}]: and nothing has been done about it.")
          end
          @watched_list[identity] = {
            :action=>action,
            :exec=>exec,
            :freq=>freq,
            :pid=>PidFile.new(identity,@pid_dir),
          }
          @watch_list_signal.signal
        else
          raise AlreadyWatched.new("The agent [#{id}] is already being watched by us.")
        end
      }
    end

    def agent_running?(identity)
      # The check method really tells us if the agent ISN'T running
      # and throws an exception if it is...poorly named I know
      @watch_list_lock.synchronize { not @watched_list[identity][:pid].check rescue true }
    end

    def check_agent(identity)
      log_info("AgentWatcher is checkin in on the #{identity} agent.")
      @watch_list_lock.synchronize do
        unless agent_running?(identity)
          agent = @watched_list.delete(identity)
          @stopped_list[identity] = agent
          agent[:action].call(identity, :stopped, "The #{identity} agent does not appear to be running!")
        end
      end
    end

  end

end
