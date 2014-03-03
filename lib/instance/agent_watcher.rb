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
    class AlreadyWatched < Exception; end
    class UnknownAgent < Exception; end

    # Some Time calculation constants
    # ===
    SECOND = 1
    MINUTE = 60 * SECOND
    HOUR = 60 * MINUTE
    DAY = 24 * HOUR
    # ===

    DEFAULT_FREQUENCY_CHECK = 5 * SECOND

    def initialize(logger, pid_dir=nil)
      @logger = logger
      @pid_dir = pid_dir
      @running = false
      @stopped_list = {}
      @watched_list = {}
      @watch_list_lock = Monitor.new
    end

    def log_info(s)
      @logger.call("AgentWatcher: #{s}")
    end

    def kill_agent(identity, signal='SIGKILL')
      @watch_list_lock.synchronize do
        raise UnknownAgent, "#{identity} is not a known agent." unless @watched_list.has_key?(identity)
        agent = @watched_list.delete(identity)
        Process.kill(signal, agent[:pid].read_pid[:pid])
        @stopped_list[identity] = agent
      end
    end

    def restart_agent(identity)
      stop_agent(identity)
      start_agent(identity)
    end

    def start_watching()
      return if @running
      # This logic is implemented with a priority queue of "next check" times:
      #
      # This allows us not to have to start a bunch of timers and do time
      # alrithmatic which can be tricky when someone goes and changes the date
      # on the system this code is running.

      # Initialize all agents
      @watch_list_lock.synchronize {
        @watched_list.each { |k, v| v[:next_check] = 0 }
      }

      log_info("Starting the AgentWatcher.")
      @agent_watcher_thread = Thread.new do
        @running = true
        while @running
          next_check = 0
          time_start = Time.now

          @watch_list_lock.synchronize do
            # No use doing anything till we have something to work on, I would have
            # rather used a ConditionVariable here, but they are not compatible with
            # Monitor objects, and I need reentrance.
            sleep DEFAULT_FREQUENCY_CHECK until @watched_list.size > 0 or not @running

            # Check all processes in the list with a next check time of zero
            # replacing the next check time with their frequency.
            # Duplicating because @watched_list can be modified(if we need to restart agent) and Ruby 1.9.3 doesn't allow it
            @watched_list.dup.each do |k,v|
              if v[:next_check] <= 0
                @watched_list[k][:next_check] = v[:freq]
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
        log_info("Shutting down.")
      end
    end

    def start_agent(identity)
      @watch_list_lock.synchronize {
        raise UnknownAgent, "#{identity} is not a known stopped agent." unless @stopped_list.has_key?(identity)
        agent = @stopped_list.delete(identity)
        agent[:pid].remove
        system("#{agent[:exec]} #{agent[:start_opts]}")
        log_info("Successfully started the #{identity} agent.")
        # Give us some time to come up before the next check...should be good in
        # 60 seconds I would think.
        agent[:next_check] = MINUTE
        @watched_list[identity] = agent
      }
    end

    def stop_watching()
      return unless @running
      log_info("Stopping the AgentWatcher.")
      @running = false
      @agent_watcher_thread.terminate
      @agent_watcher_thread.join
      @agent_watcher_thread = nil
      log_info("AgentWatcher Stopped.")
    end

    def stop_agent(identity)
      @watch_list_lock.synchronize {
        raise UnknownAgent, "#{identity} is not a known agent." unless @watched_list.has_key?(identity)
        agent = @watched_list.delete(identity)
        if system("#{agent[:exec]} #{agent[:stop_opts]}")
          log_info("Successfully stopped the #{identity} agent.")
          agent[:pid].remove
        end
        @stopped_list[identity] = agent
      }
    end

    def watch_agent(identity, exec, start_opts, stop_opts, freq=DEFAULT_FREQUENCY_CHECK)
      # Make things simple for now and require a resolution of 1 second
      # for the frequency check.
      raise BadFrequency.new unless (freq > 1)

      # Protect the watch list from the thread monitoring the agents
      @watch_list_lock.synchronize {
        unless @watched_list.has_key?(identity)

          # If we were given a block, use that for state change, otherwise restart
          action = (block_given? && Proc.new) || Proc.new do |identity, state, mesg|
            if state == :stopped
              log_info("#{identity} has stopped, restarting now.")
              self.start_agent(identity)
            end
          end

          @watched_list[identity] = {
            :action=>action,
            :exec=>exec,
            :start_opts=>start_opts,
            :stop_opts=>stop_opts,
            :freq=>freq,
            :pid=>PidFile.new(identity,@pid_dir),
          }
        else
          raise AlreadyWatched.new("The agent [#{identity}] is already being watched by us.")
        end
      }
    end

    private

    def agent_running?(identity)
      # The check method really tells us if the agent ISN'T running
      # and throws an exception if it is...poorly named I know
      @watch_list_lock.synchronize do
        begin
          @watched_list[identity][:pid].check
          false
        rescue PidFile::AlreadyRunning
          true
        end
      end
    end

    def check_agent(identity)
      @watch_list_lock.synchronize do
        test_agent = agent_running?(identity)
        unless test_agent
          agent = @watched_list.delete(identity)
          @stopped_list[identity] = agent
          agent[:action].call(identity, :stopped, "The #{identity} agent does not appear to be running!")
        end
      end
    end

  end

end
