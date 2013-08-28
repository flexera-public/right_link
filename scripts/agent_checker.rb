# === Synopsis:
#   RightScale Agent Checker (rchk) - (c) 2010-2013 RightScale Inc
#
#   Checks the agent to see if it is actively communicating with RightNet and if not
#   triggers it to re-enroll and exits.
#
#   Alternatively runs as a daemon and performs this communication check periodically.
#
# === Usage
#    rchk
#
#    Options:
#      --time-limit, -t SEC      Override the default time limit since last communication for
#                                check to pass (also the interval for daemon to run these checks),
#                                ignored if less than 1
#      --attempts, -a N          Override the default number of communication check attempts
#                                before trigger re-enroll, ignored if less than 1
#      --retry-interval, -r SEC  Override the default interval for retrying communication check,
#                                reset to time-limit if less than it, ignored if less than 1
#      --start                   Run as a daemon process that checks agent communication after the
#                                configured time limit and repeatedly thereafter on that interval
#                                (the checker does an immediate one-time check if --start is not specified)
#      --stop                    Stop the currently running daemon started with --start and then exit)
#      --ping, -p                Try communicating now regardless of whether have communicated within
#                                the configured time limit, does not apply if running as a daemon
#      --verbose, -v             Display debug information
#      --version                 Display version information
#      --help                    Display help
#

require 'rubygems'
require 'eventmachine'
require 'trollop'
require 'right_agent'
require 'right_agent/scripts/usage'
require 'right_agent/scripts/common_parser'

require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_watcher'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'lib', 'instance', 'agent_config'))
require File.expand_path(File.join(File.dirname(__FILE__), 'command_helper'))

module RightScale

  # Commands exposed by instance agent checker
  class AgentCheckerCommands

    # Build hash of commands associating command names with block
    #
    # === Parameters
    # checker(AgentChecker):: Agent checker executing commands
    #
    # === Return
    # (Hash):: Command blocks keyed by command names
    def self.get(checker)
      target = new(checker)
      {:terminate => lambda { |opts, conn| opts[:conn] = conn; target.send("terminate_command", opts) }}
    end

    # Set agent checker for executing commands
    #
    # === Parameter
    # checker(AgentChecker):: Agent checker
    def initialize(checker)
      @checker = checker
    end

    protected

    # Terminate command
    #
    # === Parameters
    # opts[:conn](EM::Connection):: Connection used to send reply
    #
    # === Return
    # true:: Always return true
    def terminate_command(opts)
      CommandIO.instance.reply(opts[:conn], "Checker terminating")
      # Delay terminate a bit to give reply a chance to be sent
      EM.next_tick { @checker.terminate }
    end

  end # AgentCheckerCommands

  class AgentChecker
    include CommandHelper
    include DaemonizeHelper

    VERSION = [0, 1]

    # Time constants
    MINUTE = 60
    HOUR = 60 * MINUTE
    DAY = 24 * HOUR

    # Default minimum seconds since last communication for instance to be considered connected
    # Only used if --time-limit not specified and :ping_interval option not specified for agent
    DEFAULT_TIME_LIMIT = 12 * HOUR

    # Multiplier of agent's mapper ping interval to get daemon's last communication time limit
    PING_INTERVAL_MULTIPLIER = 3

    # Default maximum number of seconds between checks for recent communication if first check fails
    DEFAULT_RETRY_INTERVAL = 5 * MINUTE

    # Default maximum number of attempts to check communication before trigger re-enroll
    DEFAULT_MAX_ATTEMPTS = 3

    # Maximum number of seconds to wait for a CommandIO response from the instance agent
    COMMAND_IO_TIMEOUT = 2 * MINUTE

    # Create and run checker
    #
    # === Return
    # true:: Always return true
    def self.run
      c = AgentChecker.new
      c.start(c.parse_args)
    rescue Errno::EACCES => e
      STDERR.puts e.message
      STDERR.puts "Try elevating privilege (sudo/runas) before invoking this command."
      exit(2)
    end

    # Create AgentWatcher to monitor agent processes
    #
    # === Return
    # nil
    def setup_agent_watcher()
      @agent_watcher ||= AgentWatcher.new( lambda { |s| self.info(s) }, @agent[:pid_dir] )
      @agent_watcher.watch_agent(@agent[:identity], '/opt/rightscale/bin/rnac', '--start instance', '--stop instance')
      @agent_watcher.start_watching()
    end

    # Stop AgentWatcher from monitoring agent processes
    #
    # === Return
    # nil
    def stop_agent_watcher()
      @agent_watcher.stop_agent(@agent[:identity])
      @agent_watcher.stop_watching()
    end

    # Run daemon or run one agent communication check
    # If running as a daemon, store pid in same location as agent except suffix the
    # agent identity with '-rchk'.
    #
    # === Parameters
    # options(Hash):: Run options
    #   :time_limit(Integer):: Time limit for last communication and interval for daemon checks,
    #     defaults to PING_INTERVAL_MULTIPLIER times agent's ping interval or to DEFAULT_TIME_LIMIT
    #   :max_attempts(Integer):: Maximum number of communication check attempts,
    #     defaults to DEFAULT_MAX_ATTEMPTS
    #   :retry_interval(Integer):: Number of seconds to wait before retrying communication check,
    #     defaults to DEFAULT_RETRY_INTERVAL, reset to :time_limit if exceeds it
    #   :daemon(Boolean):: Whether to run as a daemon rather than do a one-time communication check
    #   :log_path(String):: Log file directory, defaults to one used by agent
    #   :stop(Boolean):: Whether to stop the currently running daemon and then exit
    #   :ping(Boolean):: Try communicating now regardless of whether have communicated within
    #     the configured time limit, ignored if :daemon true
    #   :verbose(Boolean):: Whether to display debug information
    #
    # === Return
    # true:: Always return true
    def start(options)
      begin
        setup_traps
        @state_serializer = Serializer.new(:json)

        # Retrieve instance agent configuration options
        @agent = AgentConfig.agent_options('instance')
        error("No instance agent configured", nil, abort = true) if @agent.empty?

        # Apply agent's ping interval if needed and adjust options to make them consistent
        @options = options
        unless @options[:time_limit]
          if @agent[:ping_interval]
            @options[:time_limit] = @agent[:ping_interval] * PING_INTERVAL_MULTIPLIER
          else
            @options[:time_limit] = DEFAULT_TIME_LIMIT
          end
        end
        @options[:retry_interval] = [@options[:retry_interval], @options[:time_limit]].min
        @options[:max_attempts] = [@options[:max_attempts], @options[:time_limit] / @options[:retry_interval]].min
        @options[:log_path] ||= RightScale::Platform.filesystem.log_dir

        # Attach to log used by instance agent
        Log.program_name = 'RightLink'
        Log.facility = 'user'
        Log.log_to_file_only(@agent[:log_to_file_only])
        Log.init(@agent[:identity], @options[:log_path], :print => true)
        Log.level = :debug if @options[:verbose]
        @logging_enabled = true

        # Catch any egregious eventmachine failures, especially failure to connect to agent with CommandIO
        # Exit even if running as daemon since no longer can trust EM and should get restarted automatically
        EM.error_handler do |e|
          if e.class == RuntimeError && e.message =~ /no connection/
            error("Failed to connect to agent for communication check", nil, abort = false)
            @command_io_failures = (@command_io_failures || 0) + 1
            reenroll! if @command_io_failures > @options[:max_attempts]
          else
            error("Internal checker failure", e, abort = true)
          end
        end

        # note that our Windows service monitors rnac and rchk processes
        # externally and restarts them if they die, so no need to roll our
        # own cross-monitoring on that platform.
        use_agent_watcher = !RightScale::Platform.windows?
        EM.run do
          check
          setup_agent_watcher if use_agent_watcher
        end
        stop_agent_watcher if use_agent_watcher

      rescue SystemExit => e
        raise e
      rescue Exception => e
        error("Failed to run", e, abort = true)
      end
      true
    end

    # Terminate the checker
    #
    # === Return
    # true:: Always return true
    def terminate
      CommandRunner.stop rescue nil if @command_runner
      EM.stop rescue nil
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Command line options
    def parse_args
      parser = Trollop::Parser.new do
        opt :max_attempts, "", :default => DEFAULT_MAX_ATTEMPTS, :long => "--attempts", :short => "-a"
        opt :retry_interval, "", :default => DEFAULT_RETRY_INTERVAL
        opt :time_limit, "", :type => :int
        opt :daemon, "", :long => "--start"
        opt :stop
        opt :ping
        opt :verbose
        opt :state_path, "", :type => String
        version ""
      end
      
      parse do
        options = parser.parse
        options.delete(:max_attempts) unless options[:max_attempts] > 0
        if options[:delete]
          options.delete(:time_limit) unless options[:time_limit] > 0
        end
        options.delete(:retry_interval) unless options[:retry_interval] > 0
        options
      end
    end


protected

    # Perform required checks
    #
    # === Return
    # true:: Always return true
    def check
      begin
        checker_identity = "#{@agent[:identity]}-rchk"
        pid_file = PidFile.new(checker_identity, @agent[:pid_dir])

        if @options[:stop]
          # Stop checker
          pid_data = pid_file.read_pid
          if pid_data[:pid]
            info("Stopping checker daemon")
            if RightScale::Platform.windows?
              begin
                send_command({:name => :terminate}, verbose = @options[:verbose], timeout = 30) do |r|
                  info(r)
                  terminate
                end
              rescue Exception => e
                error("Failed stopping checker daemon, confirm it is still running", e, abort = true)
              end
            else
              Process.kill('TERM', pid_data[:pid])
              terminate
            end
          else
            terminate
          end
        elsif @options[:daemon]
          # Run checker as daemon
          pid_file.check rescue error("Cannot start checker daemon because already running", nil, abort = true)
          daemonize(checker_identity, @options) unless RightScale::Platform.windows?
          pid_file.write
          at_exit { pid_file.remove }

          listen_port = CommandConstants::BASE_INSTANCE_AGENT_CHECKER_SOCKET_PORT
          @command_runner = CommandRunner.start(listen_port, checker_identity, AgentCheckerCommands.get(self))

          info("Checker daemon options:")
          log_options = @options.inject([]) { |t, (k, v)| t << "-  #{k}: #{v}" }
          log_options.each { |l| info(l, to_console = false, no_check = true) }

          info("Starting checker daemon with #{elapsed(@options[:time_limit])} polling " +
               "and #{elapsed(@options[:time_limit])} last communication limit")

          iteration = 0
          EM.add_periodic_timer(@options[:time_limit]) do
            iteration += 1
            debug("Checker iteration #{iteration}")
            check_communication(0)
          end
        else
          # Perform one check
          check_communication(0, @options[:ping])
        end
      rescue SystemExit => e
        raise e
      rescue Exception => e
        error("Internal checker failure", e, abort = true)
      end
      true
    end

    # Check communication, repeatedly if necessary
    #
    # === Parameters
    # attempt(Integer):: Number of attempts thus far
    # must_try(Boolean):: Try communicating regardless of whether required based on time limit
    #
    # === Return
    # true:: Always return true
    def check_communication(attempt, must_try = false)
      attempt += 1
      begin
        if !must_try && (time = time_since_last_communication) < @options[:time_limit]
          @retry_timer.cancel if @retry_timer
          elapsed = elapsed(time)
          info("Passed communication check with activity as recently as #{elapsed} ago", to_console = !@options[:daemon])
          terminate unless @options[:daemon]
        elsif attempt <= @options[:max_attempts]
          debug("Trying communication" + (attempt > 1 ? ", attempt #{attempt}" : ""))
          try_communicating(attempt)
          @retry_timer = EM::Timer.new(@options[:retry_interval]) do
            error("Communication attempt #{attempt} timed out after #{elapsed(@options[:retry_interval])}")
            @agent = AgentConfig.agent_options('instance') # Reload in case not using right cookie
            check_communication(attempt)
          end
        else
          reenroll!
        end
      rescue SystemExit => e
        raise e
      rescue Exception => e
        abort = !@options[:daemon] && (attempt > @options[:max_attempts])
        error("Failed communication check", e, abort)
        check_communication(attempt)
      end
      true
    end

    # Get elapsed time since last communication
    #
    # === Return
    # (Integer):: Elapsed time
    def time_since_last_communication
      state_file = @options[:state_path] || File.join(AgentConfig.agent_state_dir, 'state.js')
      state = @state_serializer.load(File.read(state_file)) if File.file?(state_file)
      state.nil? ? (@options[:time_limit] + 1) : (Time.now.to_i - state["last_communication"])
    end

    # Ask instance agent to try to communicate
    #
    # === Parameters
    # attempt(Integer):: Number of attempts thus far
    #
    # === Return
    # true:: Always return true
    def try_communicating(attempt)
      begin
        send_command({:name => "check_connectivity"}, @options[:verbose], COMMAND_IO_TIMEOUT) do |r|
          @command_io_failures = 0
          res = serialize_operation_result(r) rescue nil
          if res && res.success?
            info("Successful agent communication" + (attempt > 1 ? " on attempt #{attempt}" : ""))
            @retry_timer.cancel if @retry_timer
            check_communication(attempt)
          else
            error = (res && result.content) || "<unknown error>"
            error("Failed agent communication attempt", error, abort = false)
            # Let existing timer control next attempt
          end
        end
      rescue Exception => e
        error("Failed to access agent for communication check", e, abort = false)
      end
      true
    end

    # Trigger re-enroll
    # This will normally cause the checker to exit
    #
    # === Return
    # true:: Always return true
    def reenroll!
      unless @reenrolling
        @reenrolling = true
        begin
          info("Triggering re-enroll after unsuccessful communication check", to_console = true)
          cmd = "rs_reenroll"
          cmd += " -v" if @options[:verbose]
          cmd += '&' unless RightScale::Platform.windows?
          # Windows relies on the command protocol to terminate properly.
          # If rchk terminates itself, then rchk --stop will hang trying
          # to connect to this rchk.
          terminate unless RightScale::Platform.windows?
          system(cmd)
          # Wait around until rs_reenroll has a chance to stop the checker
          # otherwise we may restart it
          sleep(5)
        rescue Exception => e
          error("Failed re-enroll after unsuccessful communication check", e, abort = true)
        end
        @reenrolling = false
      end
      true
    end

    # Setup signal traps
    #
    # === Return
    # true:: Always return true
    def setup_traps
      ['INT', 'TERM'].each do |sig|
        trap(sig) do
          EM.next_tick do
            terminate
            EM.stop
          end
        end
      end
      true
    end

    # Log debug information
    #
    # === Parameters
    # info(String):: Information to be logged
    #
    # === Return
    # true:: Always return true
    def debug(info)
      info(info) if @options[:verbose]
    end

    # Log information
    #
    # === Parameters
    # info(String):: Information to be logged
    # to_console(Boolean):: Whether to also display to console even if :verbose is false
    # no_check(Boolean):: Whether to omit '[check]' prefix in logged info
    #
    # === Return
    # true:: Always return true
    def info(info, to_console = false, no_check = false)
      Log.info("#{no_check ? '' : '[check] '}#{info}")
      puts(info) if @options[:verbose] || to_console
    end

    # Handle error by logging message and optionally aborting execution
    #
    # === Parameters
    # description(String):: Description of context where error occurred
    # error(Exception|String):: Exception or error message
    # abort(Boolean):: Whether to abort execution
    #
    # === Return
    # true:: If do not abort
    def error(description, error = nil, abort = false)
      if @logging_enabled
        msg = "[check] #{description}"
        msg += ", aborting" if abort
        msg = Log.format(msg, error, :trace) if error
        Log.error(msg)
      end

      msg = description
      msg += ": #{error}" if error
      puts "** #{msg}"

      if abort
        terminate
        exit(1)
      end
      true
    end

    # Convert elapsed time in seconds to displayable format
    #
    # === Parameters
    # time(Integer|Float):: Elapsed time
    #
    # === Return
    # (String):: Display string
    def elapsed(time)
      time = time.to_i
      if time <= MINUTE
        "#{time} sec"
      elsif time <= HOUR
        minutes = time / MINUTE
        seconds = time - (minutes * MINUTE)
        "#{minutes} min #{seconds} sec"
      elsif time <= DAY
        hours = time / HOUR
        minutes = (time - (hours * HOUR)) / MINUTE
        "#{hours} hr #{minutes} min"
      else
        days = time / DAY
        hours = (time - (days * DAY)) / HOUR
        minutes = (time - (days * DAY) - (hours * HOUR)) / MINUTE
        "#{days} day#{days == 1 ? '' : 's'} #{hours} hr #{minutes} min"
      end
    end

    # Version information
    #
    # === Return
    # ver(String):: Version information
    def version
      ver = "rchk #{VERSION.join('.')} - RightScale Agent Checker (c) 2013 RightScale"
    end

    def usage
      Usage.scan(__FILE__)
    end

  end # AgentChecker

end # RightScale

# Copyright (c) 2010-2011 RightScale Inc
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
