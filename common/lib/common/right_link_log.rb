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

require 'logger'
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'config', 'right_link_config'))
require 'syslog_logger' unless RightScale::RightLinkConfig[:platform].windows?
require File.join(File.dirname(__FILE__), 'multiplexer')
require File.join(File.dirname(__FILE__), 'exceptions')
require 'singleton'

module RightScale

  # Logs both to syslog and to local file
  class RightLinkLog

    include Singleton

    # Default formatter for a RightLinkLog
    class Formatter < Logger::Formatter
      @@show_time = true

      # Set whether to show time in logged messages.
      #
      # === Parameters
      # show(Boolean):: Whether time should be shown
      def show_time=(show=false)
        @@show_time = show
      end

      # Prints a log message as 'datetime progname[pid]: message' if @@show_time == true;
      # otherwise, doesn't print the datetime.
      #
      # === Parameters
      # severity(String):: Severity of event
      # time(Time):: Date-time
      # progname(String):: Program name
      # msg(Object):: Message object that can be converted to a string
      #
      # === Return
      # Formatted message
      def call(severity, time, progname, msg)
        if @@show_time
          sprintf("%s %s[%d]: %s\n", format_datetime(time), progname, Process.pid, msg2str(msg))
        else
          sprintf("%s[%d]: %s\n", progname, Process.pid, msg2str(msg))
        end
      end

      # Converts some argument to a Logger.severity() call to a string.  Regular strings
      # pass through like normal, Exceptions get formatted as "message (class)\nbacktrace",
      # and other random stuff gets put through "object.inspect".
      #
      # === Parameters
      # msg(Object):: Message object to be converted to string
      #
      # === Return
      # String
      def msg2str(msg)
        case msg
        when ::String
          msg
        when ::Exception
          "#{ msg.message } (#{ msg.class })\n" <<
            (msg.backtrace || []).join("\n")
        else
          msg.inspect
         end
       end
    end

    # Map of log levels symbols associated with corresponding Logger constant
    LEVELS_MAP = {:debug => Logger::DEBUG,
                  :info  => Logger::INFO,
                  :warn  => Logger::WARN,
                  :error => Logger::ERROR,
                  :fatal => Logger::FATAL} unless defined?(LEVELS_MAP)

    @@inverted_levels_map = nil

    # Undefine warn to prevent Kernel#warn from being called
    undef warn

    def initialize
      # Was log ever used?
      @initialized = false
    end

    # Forward all method calls to underlying Logger object created with init.
    # Return the result of only the first registered logger to keep the interface
    # consistent with that of a Logger.
    #
    # === Parameters
    # m(Symbol):: Forwarded method name
    # args(Array):: Forwarded method arguments
    #
    # === Return
    # res(Object):: Result from first registered logger
    def method_missing(m, *args)
      init unless @initialized
      @logger.level = level_from_sym(level) if @level_frozen
      res = @logger.__send__(m, *args)
    end

    # Forward all class method calls to the singleton instance to keep the interface as it was
    # prior to introducing the singleton.
    #
    # === Parameters
    # m(Symbol):: Forwarded method name
    # args(Array):: Forwarded method arguments
    #
    # === Return
    # res(Object):: Result from first the singleton
    class << self
      def method_missing(m, *args)
        RightLinkLog.instance.send(m, *args)
      end
    end

    # Map symbol log level to Logger constant
    #
    # === Parameters
    # sym(Symbol):: Log level symbol, one of :debug, :info, :warn, :error or :fatal
    #
    # === Return
    # lvl(Constant):: One of Logger::DEBUG ... Logger::FATAL
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: if level symbol is invalid
    def level_from_sym(sym)
      raise Exceptions::Argument, "Invalid log level symbol :#{sym}" unless LEVELS_MAP.include?(sym)
      lvl = LEVELS_MAP[sym]
    end

    # Map Logger log level constant to symbol
    #
    # === Parameters
    # lvl(Constant):: Log level constant, one of Logger::DEBUG ... Logger::FATAL
    #
    # === Return
    # sym(Symbol):: One of :debug, :info, :warn, :error or :fatal
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: if level is invalid
    def level_to_sym(lvl)
      @@inverted_levels_map ||= LEVELS_MAP.invert
      raise Exceptions::Argument, "Invalid log level: #{lvl}" unless @@inverted_levels_map.include?(lvl)
      sym = @@inverted_levels_map[lvl]
    end

    # Read access to internal multiplexer
    #
    # === Return
    # logger(RightScale::Multiplexer):: Multiplexer logger
    def logger
      init unless @initialized
      logger = @logger
    end

    # Add new logger to list of multiplexed loggers
    #
    # === Parameters
    # logger(Object):: Logger that should get log messages
    #
    # === Return
    # @logger(RightScale::Multiplexer):: Multiplexer logger
    def add_logger(logger)
      init unless @initialized
      logger.level = level_from_sym(RightLinkLog.instance.level)
      @logger.add(logger)
    end

    # Remove logger from list of multiplexed loggers
    #
    # === Parameters
    # logger(Object):: Logger to be removed
    #
    # === Return
    # @logger(RightScale::Multiplexer):: Multiplexer logger
    def remove_logger(logger)
      init unless @initialized
      @logger.remove(logger)
    end

    # Set whether syslog should be used or to log to an agent-specific file
    # This should be called before anything else
    #
    # === Parameters
    # val(Boolean):: Whether syslog should be used (false) or
    #                a agent-specific log file (true)
    #
    # === Raise
    # RuntimeError:: If logger is already initialized
    def log_to_file_only(val)
      raise 'Logger already initialized' if @initialized
      @log_to_file_only = !!val
    end

    # Was logger initialized?
    #
    # === Return
    # true:: if logger has been initialized
    # false:: Otherwise
    def initialized
      @initialized
    end

    # Sets the syslog program name that will be reported.
    # Can only be successfully called before logging is
    # initialized.
    #
    # === Parameters
    # prog_name(String):: An arbitrary string, or "nil" to use
    #   the default name that is based on the agent's identity
    #
    # === Return
    # program_name(String):: The input string
    #
    # === Raise
    # RuntimeError:: If logger is already initialized
    def program_name=(prog_name)
      raise 'Logger already initialized' if @initialized
      @program_name = prog_name
    end

    # Sets the level for the Logger by symbol or by Logger constant
    #
    # === Parameters
    # level(Object):: One of :debug, :info, :warn, :error, :fatal or
    #                 one of "debug", "info", "warn", "error", "fatal" or
    #                 one of Logger::INFO ... Logger::FATAL
    #
    # === Return
    # level(Symbol):: New log level, or current level if frozen
    def level=(level)
      init unless @initialized
      unless @level_frozen
        new_level = case level
          when Symbol then
            level_from_sym(level)
          when String then
            level_from_sym(level.to_sym)
          else
            level
        end
        if new_level != @level
          @logger.info("[setup] Setting log level to #{level_to_sym(new_level).to_s.upcase}")
          @logger.level = @level = new_level
        end
      end
      level = level_to_sym(@level)
    end

    # Current log level
    #
    # === Return
    # level(Symbol):: One of :debug, :info, :warn, :error or :fatal
    def level
      init unless @initialized
      level = level_to_sym(@level)
    end

    # Force log level to debug and disregard
    # any further attempt to change it
    #
    # === Return
    # true:: Always return true
    def force_debug
      self.level = :debug
      @level_frozen = true
    end

    protected

    # Initialize logger
    #
    # === Parameters
    # identity(String):: Log identity
    # path(String):: Log directory path
    #
    # === Return
    # logger(RightScale::Multiplexer):: logger instance
    def init(identity = nil, path = nil)
      unless @initialized
        @initialized = true
        @level_frozen = false
        logger = nil

        if @log_to_file_only || RightLinkConfig[:platform].windows?
          if path
            file = File.join(path, "#{identity}.log")
          else
            file = STDOUT
          end
          logger = Logger.new(file)
          logger.formatter = Formatter.new
          logger.progname = @program_name || identity || 'RightLink'
          logger.formatter.datetime_format = "%b %d %H:%M:%S"
        else
          logger = SyslogLogger.new(@program_name || identity || 'RightLink')
        end

        @logger = Multiplexer.new(logger)
        self.level = :info
      end
      @logger
    end

  end # RightLinkLog

end # RightScale
