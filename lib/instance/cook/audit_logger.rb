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

require 'logger'
require 'chef'
require 'chef/formatters/base'

module RightScale

  # Audit logger formatter
  class AuditLogFormatter < ::Logger::Formatter
    MASKED_INPUT_TEXT = '<hidden input %s>'

    def initialize(filtered_inputs={})
      @filtered_inputs = filtered_inputs
    end

    # Generate log line from given input
    def call(severity, time, progname, msg)
      sprintf("%s: %s\n", time.strftime("%H:%M:%S"), hide_inputs(msg2str(msg)))
    end

    def hide_inputs(msg)
      @filtered_inputs.reduce(msg) do |m, (k, v)|
        pattern = [v].flatten.map { |p| Regexp.escape(p) }.join("|")
        m = m.gsub(/\b#{pattern}\b/, MASKED_INPUT_TEXT % [k])
      end
    end

  end

  # Provides logger interface but forwards some logging to audit entry.
  # Used in combination with Chef to audit recipe execution output.
  class AuditLogger < ::Logger

    # Underlying audit id
    attr_reader :audit_id

    # Initialize audit logger, override Logger initialize since there is no need to initialize @logdev
    #
    # === Parameters
    # audit_id(Integer):: Audit id used to audit logs
    def initialize(filtered_inputs=nil)
      @progname = nil
      @level = INFO
      @default_formatter = AuditLogFormatter.new(filtered_inputs)
      @formatter = nil
      @logdev = nil
    end

    # Return level as a symbol
    #
    # === Return
    # level(Symbol):: One of :debug, :info, :warn, :error or :fatal
    alias :level_orig :level
    def level
      level = { Logger::DEBUG => :debug,
                Logger::INFO  => :info,
                Logger::WARN  => :warn,
                Logger::ERROR => :error,
                Logger::FATAL => :fatal }[level_orig]
    end

    # Raw output
    #
    # === Parameters
    # msg(String):: Raw string to be appended to audit
    def <<(msg)
      AuditStub.instance.append_output(msg)
    end

    # Override Logger::add to audit instead of writing to log file
    #
    # === Parameters
    # severity(Constant):: One of Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::ERROR or Logger::FATAL
    # message(String):: Message to be audited
    # progname(String):: Override default program name for that audit
    #
    # === Block
    # Call given Block if any to build message if +message+ is nil
    #
    # === Return
    # true:: Always return true
    def add(severity, message=nil, progname=nil, &block)
      severity ||= UNKNOWN
      # We don't want to audit logs that are less than our level
      return true if severity < @level
      progname ||= @progname
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = @progname
        end
      end
      return true if is_filtered?(severity, message)
      msg = format_message(format_severity(severity), Time.now, progname, message)
      case severity
      when Logger::INFO, Logger::WARN, Logger::UNKNOWN, Logger::DEBUG
        AuditStub.instance.append_output(msg)
      when Logger::ERROR
        AuditStub.instance.append_error(msg)
      when Logger::FATAL
        AuditStub.instance.append_error(msg, :category => RightScale::EventCategories::CATEGORY_ERROR)
      end
      true
    end

    # Start new audit section
    # Note: This is a special 'log' method which allows us to create audit sections before
    # running RightScripts
    #
    # === Parameters
    # title(String):: Title of new audit section, will replace audit status as well
    # options[:category](String):: Optional, must be one of RightScale::EventCategories::CATEGORIES
    #
    # === Return
    # true:: Always return true
    def create_new_section(title, options={})
      AuditStub.instance.create_new_section(title, options)
    end

    protected

    MESSAGE_FILTERS = {
      Logger::ERROR => [
        # Suppress the auditing of anything Chef logs with ERROR severity that
        # concerns itself with the right_scripts_cookbook. This cookbook is
        # dynamically generated by the instance and concerns itself with
        # RightScripts, which have their own independent mechanism for auditing
        # failures.
        #
        # There are two flavors of this suppression: one for Linux, one for Windows.
        # This is because Windows-generated RightScript recipes have slightly different
        # naming conventions than Linux-generated.
        %r{\(right_scripts_cookbook::.+ line \d+\)},
        %r{\(right_scripts_cookbook::.+\.ps1 line .+\.ps1\.rb\)}
      ]
    }

    # Filters any message which should not appear in audits.
    #
    # === Parameters
    # severity(Constant):: One of Logger::DEBUG, Logger::INFO, Logger::WARN, Logger::ERROR or Logger::FATAL
    # message(String):: Message to be audited
    def is_filtered?(severity, message)
      if filters = MESSAGE_FILTERS[severity]
        filters.each do |filter|
          return true if filter =~ message
        end
      end
      return false
    end
  end # AuditLogger
end # RightScale

# TEAL HACK we have to monkey-patch Chef's Formatter & Outputter classes because
# they exist as a channel containing important debugging information which is
# separate from the original (easily understandable) Chef::Log. the Outputter
# lacks log level but the Formatter knows when it is displaying an error. the
# point of the new formatting appears to be to print colors when running chef at
# the console but this is no good reason for them to ignore standard log levels.
class Chef
  module Formatters
    class Base
      def display_error(description)
        section = description.sections && description.sections.first
        ignore_execeptions = ["SystemExit", "RightScale::Exceptions::RightScriptExec"]
        # ignored due to rs_shutdown provider behavior
        # or useless error description for right_script and powershell providers
        unless section && !(section.keys & ignore_execeptions).empty?
          last_output_log_level = output.output_log_level if output.respond_to?(:output_log_level)
          begin
            output.output_log_level = :error if output.respond_to?(:output_log_level)
            puts("")
            description.display(output)
          ensure
            output.output_log_level = last_output_log_level if output.respond_to?(:output_log_level)
          end
        end
      end
    end # Base

    # chef defaults to using null formatter (without an outputter due to our
    # custom chef chef gem) when STDOUT.tty? == false so supress all but error-
    # level logging when null formatter is used.
    class NullFormatter
      attr_accessor :output_log_level

      def default_output_log_level
        :debug
      end

      def color(*args)
        write_to_log(args.first)
      end

      def print(*args)
        write_to_log(args.first)
      end

      def puts(*args)
        write_to_log(args.first)
      end

      private

      def write_to_log(string)
        ::Chef::Log.method(output_log_level || default_output_log_level).call(string)
      end
    end # NullFormatter

    class Outputter
      attr_accessor :output_log_level

      def default_output_log_level
        :info
      end

      def color(*args)
        write_to_log(args.first)
      end

      def print(*args)
        write_to_log(args.first)
      end

      def puts(*args)
        write_to_log(args.first)
      end

      private

      def write_to_log(string)
        ::Chef::Log.method(output_log_level || default_output_log_level).call(string)
      end
    end # Outputter
  end # Formatters
end # Chef
