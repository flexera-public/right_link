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

module RightScale

  # Provides logger interface but forwards logging to audit entry
  # Used in combination with Chef to audit recipe execution output
  class AuditLogger < ::Logger

    # Initialize audit logger, override Logger initialize since there is no need to initialize @logdev
    #
    # === Parameters
    # auditor<RightScale::AuditorProxy>:: Audit proxy used to audit logs
    def initialize(auditor)
      @auditor = auditor
      @progname = nil
      @level = DEBUG
      @default_formatter = Formatter.new
      @formatter = nil
      @logdev = nil
    end

    # Raw output
    #
    # === Parameters
    # msg<String>:: Raw string to be appended to audit
    def <<(msg)
      @auditor.append_raw_output(msg)
    end

    # Override Logger::add to audit instead of writing to log file
    #
    # === Parameters
    # severity<Constant>:: One of Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::ERROR or Logger::FATAL
    # message<String>:: Message to be audited
    # progname<String>:: Override default program name for that audit
    #
    # === Block
    # Call given Block if any to build message if +message+ is nil
    #
    # === Return
    # true:: Always return true
    def add(severity, message=nil, progname=nil, &block)
      severity ||= UNKNOWN
      # We don't want to audit debug logs
      return true if severity < @level || severity == DEBUG
      progname ||= @progname
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = @progname
        end
      end
      msg = format_message(format_severity(severity), Time.now, progname, message)
      case severity
      when Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::UNKNOWN
        @auditor.append_info(msg)
      when Logger::ERROR, Logger::FATAL
        @auditor.append_error(msg)
      end
      true
    end

  end

end