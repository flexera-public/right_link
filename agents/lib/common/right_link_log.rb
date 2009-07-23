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
 
module RightScale

  # Logs both to syslog and to local file
  class RightLinkLog

    # Forward all method calls to multiplexer
    def self.method_missing(m, *args)
      self.init unless @initialized
      res = @logger.__send__(m, *args)
    end

    # Read access to internal multiplexer
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
      @logger.add(logger)
      @logger
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
      @logger
    end
  
    protected

    # Was log ever used?
    @initialized = false

    # Initialize logger so it multiplexes to both syslog and Nanite's log
    #
    # === Return
    # logger<RightScale::Multiplexer>:: logger instance
    def self.init
      unless @initialized
        raise 'Initialize Nanite logger first' unless Nanite::Log.logger
        @initialized = true
        prog_name = Nanite::Log.file.match(/nanite\.(.*)\.log/)[1] rescue 'right_link'
        sysloger = SyslogLogger.new(prog_name) unless RightLinkConfig[:platform].windows?
		    @logger = Multiplexer.new(Nanite::Log.logger)
    		@logger.add(sysloger) if sysloger
        # Now make nanite use this logger
        Nanite::Log.logger = @logger
      end
    end

  end

end
