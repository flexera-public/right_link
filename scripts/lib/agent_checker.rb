# === Synopsis:
#   RightScale Agent Checker (rchk)
#   (c) 2010 RightScale
#
#   Checks the agent to see if it is actively communicating with RightNet and if not
#   triggers it to re-enroll and exits.
#
#   Alternatively runs as a daemon and performs this communication check periodically,
#   as well as optionally monitoring monit. Normally it is run as a daemon under monit
#   control, since it relies on monit to restart it if it triggers an agent re-enroll
#   or encounters fatal internal checker errors.
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
#      --stop                    Stop the currently running daemon started with --start and then exit
#                                (normally this is only used via monit, e.g., 'monit stop checker',
#                                otherwise the --stop request may be undone by monit restarting the checker)
#      --monit [SEC]             If running as a daemon, also monitor monit on a SEC second polling
#                                interval if monit is configured, SEC ignored if less than 1
#      --ping, -p                Try communicating now regardless of whether have communicated within
#                                the configured time limit, does not apply if running as a daemon
#      --verbose, -v             Display debug information
#      --version                 Display version information
#      --help                    Display help
#

require 'rubygems'
require 'eventmachine'
require 'optparse'
require 'fileutils'
require 'rdoc/usage'

BASE_DIR = File.join(File.dirname(__FILE__), '..', '..')

require File.expand_path(File.join(BASE_DIR, 'config', 'right_link_config'))
require File.normalize_path(File.join(BASE_DIR, 'command_protocol', 'lib', 'command_protocol'))
require File.normalize_path(File.join(BASE_DIR, 'common', 'lib', 'common', 'daemonize'))
require File.normalize_path(File.join(BASE_DIR, 'scripts', 'lib', 'agent_utils'))
require File.normalize_path(File.join(BASE_DIR, 'scripts', 'lib', 'rdoc_patch'))

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

    include Utils
    include DaemonizeHelper

    VERSION = [0, 1]

    # Default minimum seconds since last communication for instance to be considered connected
    # Only used if --time-limit not specified and :ping_interval option not specified for agent
    DEFAULT_TIME_LIMIT = 12 * 60 * 60

    # Multiplier of agent's mapper ping interval to get daemon's last communication time limit
    PING_INTERVAL_MULTIPLIER = 3

    # Default maximum number of seconds between checks for recent communication if first check fails
    DEFAULT_RETRY_INTERVAL = 5 * 60

    # Default maximum number of attempts to check communication before trigger re-enroll
    DEFAULT_MAX_ATTEMPTS = 3

    # Maximum number of seconds to wait for a CommandIO response from the instance agent
    COMMAND_IO_TIMEOUT = 2 * 60

    # Monit files
    MONIT = "/opt/rightscale/sandbox/bin/monit"
    MONIT_CONFIG = "/opt/rightscale/etc/monitrc"
    MONIT_PID_FILE = "/opt/rightscale/var/run/monit.pid"

    # default number of seconds between monit checks
    DEFAULT_MONIT_CHECK_INTERVAL = 5 * 60

    # Maximum number of repeated monit monitoring failures before disable monitoring monit
    MAX_MONITORING_FAILURES = 10

    # Time constants
    MINUTE = 60
    HOUR = 60 * MINUTE
    DAY = 24 * HOUR

    # Run daemon or run one agent communication check
    # If running as a daemon, store pid in same location as agent except suffix the
    # agent identity with '-rchk' (per monit setup in agent deployer)
    # Assuming that if running as daemon, monit is monitoring this daemon and
    # thus okay to abort in certain failure situations and let monit restart
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
    #   :monit(String|nil):: Directory containing monit configuration, which is to be monitored
    #   :ping(Boolean):: Try communicating now regardless of whether have communicated within
    #     the configured time limit, ignored if :daemon true
    #   :verbose(Boolean):: Whether to display debug information
    #
    # === Return
    # true:: Always return true
    def run(options)
      begin
        setup_traps
        @command_serializer = Serializer.new
        @state_serializer = Serializer.new(:json)

        # Retrieve instance agent configuration options
        @agent = agent_options('instance')
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
        @options[:log_path] ||= RightLinkConfig[:platform].filesystem.log_dir

        # Attach to log used by instance agent
        RightLinkLog.program_name = 'RightLink'
        RightLinkLog.log_to_file_only(@agent[:log_to_file_only])
        RightLinkLog.init(@agent[:identity], @options[:log_path], :print => true)
        RightLinkLog.level = :debug if @options[:verbose]
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

        EM.run { check }

        info("Checker exiting") if @options[:daemon]

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
      RightScale::CommandRunner.stop rescue nil if @command_runner
      EM.stop rescue nil
      true
    end

    # Create options hash from command line arguments
    #
    # === Return
    # options(Hash):: Command line options
    def parse_args
      options = {
        :max_attempts   => DEFAULT_MAX_ATTEMPTS,
        :retry_interval => DEFAULT_RETRY_INTERVAL,
        :verbose        => false
      }

      opts = OptionParser.new do |opts|

        opts.on('-t', '--time-limit SEC') do |sec|
          options[:time_limit] = sec.to_i if sec.to_i > 0
        end

        opts.on('-a', '--attempts N') do |n|
          options[:max_attempts] = n.to_i if n.to_i > 0
        end

        opts.on('-r', '--retry-interval SEC') do |sec|
          options[:retry_interval] = sec.to_i if sec.to_i > 0
        end

        opts.on('--start') do
          options[:daemon] = true
        end

        opts.on('--stop') do
          options[:stop] = true
        end

        opts.on('--monit [SEC]') do |sec|
          options[:monit] = (sec && sec.to_i > 0) ? sec.to_i : DEFAULT_MONIT_CHECK_INTERVAL
        end

        opts.on('-p', '--ping') do
          options[:ping] = true
        end

        opts.on('-v', '--verbose') do
          options[:verbose] = true
        end

        # This option is only for test purposes
        opts.on('--state-path PATH') do |path|
          options[:state_path] = path
        end

      end

      opts.on_tail('--version') do
        puts version
        exit
      end

      opts.on_tail('--help') do
         RDoc::usage_from_file(__FILE__)
         exit
      end

      begin
        opts.parse!(ARGV)
      rescue SystemExit => e
        raise e
      rescue Exception => e
        error("#{e}\nUse --help for additional information", nil, abort = true)
      end
      options
    end

protected

    # Perform required checks
    #
    # === Return
    # true:: Always return true
    def check
      begin
        checker_identity = "#{@agent[:identity]}-rchk"
        pid_file = PidFile.new(checker_identity, @agent)

        if @options[:stop]
          # Stop checker
          pid_data = pid_file.read_pid
          if pid_data[:pid]
            info("Stopping checker daemon")
            if RightLinkConfig[:platform].windows?
              begin
                client = CommandClient.new(pid_data[:listen_port], pid_data[:cookie])
                client.send_command({:name => :terminate}, verbose = @options[:verbose], timeout = 30) do |r|
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
          daemonize(checker_identity, @options) unless RightLinkConfig[:platform].windows?
          pid_file.write
          at_exit { pid_file.remove }

          listen_port = CommandConstants::BASE_INSTANCE_AGENT_CHECKER_SOCKET_PORT
          @command_runner = CommandRunner.start(listen_port, checker_identity, AgentCheckerCommands.get(self), @agent)

          info("Checker daemon options:")
          log_options = @options.inject([]) { |t, (k, v)| t << "-  #{k}: #{v}" }
          log_options.each { |l| info(l, to_console = false, no_check = true) }

          check_interval, check_modulo = if @options[:monit]
            [[@options[:monit], @options[:time_limit]].min, [@options[:time_limit] / @options[:monit], 1].max]
          else
            [@options[:time_limit], 1]
          end

          info("Starting checker daemon with #{elapsed(check_interval)} polling " +
               "and #{elapsed(@options[:time_limit])} last communication limit")

          iteration = 0
          EM.add_periodic_timer(check_interval) do
            iteration += 1
            debug("Checker iteration #{iteration}")
            check_monit if @options[:monit]
            check_communication(0) if iteration.modulo(check_modulo) == 0
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

    # Check whether monit is running and restart it if not
    # Do not start monit if it has never run, as indicated by missing pid file
    # Disable monit monitoring if exceed maximum repeated failures
    #
    # === Return
    # true:: Always return true
    def check_monit
      begin
        pid = File.read(MONIT_PID_FILE).to_i if File.file?(MONIT_PID_FILE)
        debug("Checking monit with pid #{pid.inspect}")
        if pid && !process_running?(pid)
          error("Monit not running, restarting it now")
          if system("#{MONIT} -c #{MONIT_CONFIG}")
            info("Successfully restarted monit")
          end
        end
        @monitoring_failures = 0
      rescue Exception => e
        @monitoring_failures = (@monitoring_failures || 0) + 1
        error("Failed monitoring monit", e, abort = false)
        if @monitoring_failures > MAX_MONITORING_FAILURES
          info("Disabling monitoring of monit after #{@monitoring_failures} repeated failures")
          @options[:monit] = false
        end
      end
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
            @agent = agent_options('instance') # Reload in case not using right cookie
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
      state_file = @options[:state_path] || File.join(RightScale::RightLinkConfig[:agent_state_dir], 'state.js')
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
        listen_port = @agent[:listen_port]
        client = CommandClient.new(listen_port, @agent[:cookie])
        client.send_command({:name => "check_connectivity"}, @options[:verbose], COMMAND_IO_TIMEOUT) do |r|
          @command_io_failures = 0
          res = OperationResult.from_results(@command_serializer.load(r)) rescue nil
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
          cmd += '&' unless Platform.windows?
          # Windows relies on the command protocol to terminate properly.
          # If rchk terminates itself, then rchk --stop will hang trying
          # to connect to this rchk.
          terminate unless Platform.windows?
          system(cmd)
          # Wait around until rs_reenroll has a chance to stop the checker via monit
          # otherwise monit may restart it
          sleep(5)
        rescue Exception => e
          error("Failed re-enroll after unsuccessful communication check", e, abort = true)
        end
        @reenrolling = false
      end
      true
    end

    # Checks whether process with given pid is running
    #
    # === Parameters
    # pid(Fixnum):: Process id to be checked
    #
    # === Return
    # (Boolean):: true if process is running, otherwise false
    def process_running?(pid)
      return false unless pid
      Process.getpgid(pid) != -1
    rescue Errno::ESRCH
      false
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
      RightLinkLog.info("#{no_check ? '' : '[check] '}#{info}")
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
        if error
          if error.is_a?(Exception)
            msg += ": #{error}\n" + error.backtrace.join("\n")
          else
            msg += ": #{error}"
          end
        end
        RightLinkLog.error(msg)
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
      ver = "rchk #{VERSION.join('.')} - RightScale Agent Checker (c) 2010 RightScale"
    end

  end # AgentChecker

end # RightScale

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
