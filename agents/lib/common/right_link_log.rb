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

require 'syslog_logger' unless RightScale::RightLinkConfig[:platform].windows?
require File.join(File.dirname(__FILE__), 'multiplexer')
require File.join(File.dirname(__FILE__), 'exceptions')

module RightScale

  # Logs both to syslog and to local file
  class RightLinkLog

    # Map of log levels symbols associated with corresponding Logger constant
    LEVELS_MAP = { :debug => Logger::DEBUG,
                   :info  => Logger::INFO,
                   :warn  => Logger::WARN,
                   :error => Logger::ERROR,
                   :fatal => Logger::FATAL }

    # Forward all method calls to multiplexer
    # We want to return the result of only the first registered
    # logger to keep the interface consistent with that of a Logger
    #
    # === Parameters
    # m<Symbol>:: Forwarded method name
    # args<Array>:: Forwarded method arguments
    #
    # === Return
    # res<Object>:: Result from first registered logger
    def self.method_missing(m, *args)
      self.init unless @initialized
      res = @logger.__send__(m, *args)
      res = res[0] if res && !res.empty?
      res
    end

    # Map symbol log level to Logger constant
    #
    # === Parameters
    # sym<Symbol>:: Log level symbol, one of :debug, :info, :warn, :error or :fatal
    #
    # === Return
    # lvl<Constant>:: One of Logger::DEBUG ... Logger::FATAL
    #
    # === Raise
    # <RightScale::Exceptions::Argument>:: if level symbol is invalid
    def self.level_from_sym(sym)
      raise Exceptions::Argument, "Invalid log level symbol :#{sym}" unless LEVELS_MAP.include?(sym)
      lvl = LEVELS_MAP[sym]
    end

    # Map Logger log level constant to symbol
    #
    # === Parameters
    # lvl<Constant>:: Log level constant, one of Logger::DEBUG ... Logger::FATAL
    #
    # === Return
    # sym<Symbol>:: One of :debug, :info, :warn, :error or :fatal
    #
    # === Raise
    # <RightScale::Exceptions::Argument>:: if level is invalid
    def self.level_to_sym(lvl)
      reverted_map ||= LEVELS_MAP.invert
      raise Exceptions::Argument, "Invalid log level: #{lvl}" unless reverted_map.include?(lvl)
      sym = reverted_map[lvl]
    end

    # Read access to internal multiplexer
    #
    # === Return
    # logger<RightScale::Multiplexer>:: Multiplexer logger
    def self.logger
      self.init unless @initialized
      logger = @logger
    end

    # Add new logger to list of multiplexed loggers
    #
    # === Parameters
    # logger<Object>:: Logger that should get log messages
    #
    # === Return
    # @logger<RightScale::Multiplexer>:: Multiplexer logger
    def self.add_logger(logger)
      self.init unless @initialized
      logger.level = @logger.level[0]
      @logger.add(logger)
    end

    # Remove logger from list of multiplexed loggers
    #
    # === Parameters
    # logger<Object>:: Logger to be removed
    #
    # === Return
    # @logger<RightScale::Multiplexer>:: Multiplexer logger
    def self.remove_logger(logger)
      self.init unless @initialized
      @logger.remove(logger)
    end

    # Set whether syslog should be used
    # If true then use standard Nanite logger instead
    # This should be called before anything else
    #
    # === Parameters
    # val<Boolean>:: Whether syslog should be used (false) or the
    #                standard nanite logger (true)
    #
    # === Raise
    # RuntimeError:: if logger is already initialized
    def self.log_to_file_only(val)
      raise 'Logger already initialized' if @initialized
      @log_to_file_only = !!val
    end

    # Was logger initialized?
    #
    # === Return
    # true:: if logger has been initialized
    # false:: Otherwise
    def self.initialized
      @initialized
    end

    # Sets the level for the Logger by symbol or by Logger constant
    #
    # === Parameters
    # loglevel<Object>:: One of :debug, :info, :warn, :error, :fatal or
    #                    one of Logger::INFO ... Logger::FATAL
    #
    # === Return
    # loglevel<Object>:: New loglevel
    def self.level=(loglevel)
      self.init unless @initialized
      lvl = loglevel.is_a?(Symbol) ? level_from_sym(loglevel) : loglevel
      @level = lvl
      @logger.level = lvl
      loglevel
    end

    # Current log level
    #
    # === Return
    # loglevel<Symbol>:: One of :debug, :info, :warn, :error or :fatal
    def self.level
      self.init unless @initialized
      loglevel = level_to_sym(@level)
    end

    protected

    # Was log ever used?
    @initialized = false

    # Initialize logger, must be called after Nanite logger is initialized
    #
    # === Return
    # logger<RightScale::Multiplexer>:: logger instance
    #
    # === Raise
    # RuntimeError:: If nanite logger isn't initialized
    def self.init
      unless @initialized
        raise 'Initialize Nanite logger first' unless Nanite::Log.logger
        @initialized = true
        logger = nil
        if @log_to_file_only || RightLinkConfig[:platform].windows?
          logger = Nanite::Log.logger
        else
          prog_name = Nanite::Log.file.match(/nanite\.(.*)\.log/)[1] rescue 'right_link'
          logger = SyslogLogger.new(prog_name)
          logger.level = Nanite::Log.logger.level
        end
		@logger = Multiplexer.new(logger)
        RightLinkLog.level = Nanite::Log.level
        # Now make nanite use this logger
        Nanite::Log.logger = @logger
      end
    end

  end

end
