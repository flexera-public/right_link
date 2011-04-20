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

module RightScale

  # Mixin for collecting and displaying operational statistics for servers
  module StatsHelper

    # Maximum characters in stat name
    MAX_STAT_NAME_WIDTH = 11

    # Maximum characters in sub-stat name
    MAX_SUB_STAT_NAME_WIDTH = 17

    # Maximum characters in sub-stat value line
    MAX_SUB_STAT_VALUE_WIDTH = 80

    # Maximum characters displayed for exception message
    MAX_EXCEPTION_MESSAGE_WIDTH = 60

    # Separator between stat name and stat value
    SEPARATOR = " : "

    # Time constants
    MINUTE = 60
    HOUR = 60 * MINUTE
    DAY = 24 * HOUR

    # Track activity statistics
    class ActivityStats

      # Number of samples included when calculating average recent activity
      # with the smoothing formula A = ((A * (RECENT_SIZE - 1)) + V) / RECENT_SIZE,
      # where A is the current recent average and V is the new activity value
      # As a rough guide, it takes approximately 2 * RECENT_SIZE activity values
      # at value V for average A to reach 90% of the original difference between A and V
      # For example, for A = 0, V = 1, RECENT_SIZE = 3 the progression for A is
      # 0, 0.3, 0.5, 0.7, 0.8, 0.86, 0.91, 0.94, 0.96, 0.97, 0.98, 0.99, ...
      RECENT_SIZE = 3

      # Maximum string length for activity type
      MAX_TYPE_SIZE = 60

      # (Integer) Total activity count
      attr_reader :total

      # (Hash) Count of activity per type
      attr_reader :count_per_type

      # Initialize activity data
      #
      # === Parameters
      # measure_rate(Boolean):: Whether to measure activity rate
      def initialize(measure_rate = true)
        @measure_rate = measure_rate
        @interval = 0.0
        @last_start_time = Time.now
        @avg_duration = nil
        @total = 0
        @count_per_type = {}
        @last_type = nil
        @last_id = nil
      end

      # Mark the start of an activity and update counts and average rate
      # with weighting toward recent activity
      # Ignore the update if its type contains "stats"
      #
      # === Parameters
      # type(String|Symbol):: Type of activity, with anything that is not a symbol, true, or false
      #   automatically converted to a String and truncated to MAX_TYPE_SIZE characters,
      #   defaults to nil
      # id(String):: Unique identifier associated with this activity
      #
      # === Return
      # now(Time):: Update time
      def update(type = nil, id = nil)
        now = Time.now
        if type.nil? || !(type =~ /stats/)
          @interval = average(@interval, now - @last_start_time) if @measure_rate
          @last_start_time = now
          @total += 1
          unless type.nil?
            unless [Symbol, TrueClass, FalseClass].include?(type.class)
              type = type.inspect unless type.is_a?(String)
              type = type[0, MAX_TYPE_SIZE - 3] + "..." if type.size > (MAX_TYPE_SIZE - 3)
            end
            @count_per_type[type] = (@count_per_type[type] || 0) + 1
          end
          @last_type = type
          @last_id = id
        end
        now
      end

      # Mark the finish of an activity and update the average duration
      #
      # === Parameters
      # start_time(Time):: Time when activity started, defaults to last time update was called
      # id(String):: Unique identifier associated with this activity
      #
      # === Return
      # duration(Float):: Activity duration in seconds
      def finish(start_time = nil, id = nil)
        now = Time.now
        start_time ||= @last_start_time
        duration = now - start_time
        @avg_duration = average(@avg_duration || 0.0, duration)
        @last_id = 0 if id && id == @last_id
        duration
      end

      # Convert average interval to average rate
      #
      # === Return
      # (Float|nil):: Recent average rate, or nil if total is 0
      def avg_rate
        if @total > 0
          if @interval == 0.0 then 0.0 else 1.0 / @interval end
        end
      end


      # Get average duration of activity
      #
      # === Return
      # (Float|nil) Average duration in seconds of activity weighted toward recent activity, or nil if total is 0
      def avg_duration
        @avg_duration if @total > 0
      end

      # Get stats about last activity
      #
      # === Return
      # (Hash|nil):: Information about last activity, or nil if the total is 0
      #   "elapsed"(Integer):: Seconds since last activity started
      #   "type"(String):: Type of activity if specified, otherwise omitted
      #   "active"(Boolean):: Whether activity still active
      def last
        if @total > 0
          result = {"elapsed" => (Time.now - @last_start_time).to_i}
          result["type"] = @last_type if @last_type
          result["active"] = @last_id != 0 if !@last_id.nil?
          result
        end
      end

      # Convert count per type into percentage by type
      #
      # === Return
      # (Hash|nil):: Converted counts, or nil if total is 0
      #   "total"(Integer):: Total activity count
      #   "percent"(Hash):: Percentage for each type of activity if tracking type, otherwise omitted
      def percentage
        if @total > 0
          percent = {}
          @count_per_type.each { |k, v| percent[k] = (v / @total.to_f) * 100.0 }
          {"percent" => percent, "total" => @total}
        end
      end

      # Get stat summary including all aspects of activity that were measured except duration
      #
      # === Return
      # (Hash|nil):: Information about activity, or nil if the total is 0
      #   "total"(Integer):: Total activity count
      #   "percent"(Hash):: Percentage for each type of activity if tracking type, otherwise omitted
      #   "last"(Hash):: Information about last activity
      #     "elapsed"(Integer):: Seconds since last activity started
      #     "type"(String):: Type of activity if tracking type, otherwise omitted
      #     "active"(Boolean):: Whether activity still active if tracking whether active, otherwise omitted
      #   "rate"(Float):: Recent average rate if measuring rate, otherwise omitted
      def all
        if @total > 0
          result = if @count_per_type.empty?
            {"total" => @total}
          else
            percentage
          end
          result.merge!("last" => last)
          result.merge!("rate" => avg_rate) if @measure_rate
          result
        end
      end

      protected

      # Calculate smoothed average with weighting toward recent activity
      #
      # === Parameters
      # current(Float|Integer):: Current average value
      # value(Float|Integer):: New value
      #
      # === Return
      # (Float):: New average
      def average(current, value)
        ((current * (RECENT_SIZE - 1)) + value) / RECENT_SIZE.to_f
      end

    end # ActivityStats

    # Track exception statistics
    class ExceptionStats

      # Maximum number of recent exceptions to track per category
      MAX_RECENT_EXCEPTIONS = 10

      # (Hash) Exceptions raised per category with keys
      #   "total"(Integer):: Total exceptions for this category
      #   "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
      attr_reader :stats
      alias :all :stats

      # Initialize exception data
      #
      # === Parameters
      # server(Object):: Server where exceptions are originating, must be defined for callbacks
      # callback(Proc):: Block with following parameters to be activated when an exception occurs
      #   exception(Exception):: Exception
      #   message(Packet):: Message being processed
      #   server(Server):: Server where exception occurred
      def initialize(server = nil, callback = nil)
        @server = server
        @callback = callback
        @stats = nil
      end

      # Track exception statistics and optionally make callback to report exception
      # Catch any exceptions since this function may be called from within an EM block
      # and an exception here would then derail EM
      #
      # === Parameters
      # category(String):: Exception category
      # exception(Exception):: Exception
      #
      # === Return
      # true:: Always return true
      def track(category, exception, message = nil)
        begin
          @callback.call(exception, message, @server) if @server && @callback && message
          @stats ||= {}
          exceptions = (@stats[category] ||= {"total" => 0, "recent" => []})
          exceptions["total"] += 1
          recent = exceptions["recent"]
          last = recent.last
          if last && last["type"] == exception.class.name && last["message"] == exception.message && last["where"] == exception.backtrace.first
            last["count"] += 1
            last["when"] = Time.now.to_i
          else
            backtrace = exception.backtrace.first if exception.backtrace
            recent.shift if recent.size >= MAX_RECENT_EXCEPTIONS
            recent.push({"count" => 1, "when" => Time.now.to_i, "type" => exception.class.name,
                         "message" => exception.message, "where" => backtrace})
          end
        rescue Exception => e
          RightLinkLog.error("Failed to track exception '#{exception}' due to: #{e}\n" + e.backtrace.join("\n")) rescue nil
        end
        true
      end

    end # ExceptionStats

    # Convert 0 value to nil
    # This is in support of displaying "none" rather than 0
    #
    # === Parameters
    # value(Integer|Float):: Value to be converted
    #
    # === Returns
    # (Integer|Float|nil):: nil if value is 0, otherwise the original value
    def nil_if_zero(value)
      value == 0 ? nil : value
    end

    # Convert values hash into percentages
    #
    # === Parameters
    # values(Hash):: Values to be converted whose sum is the total for calculating percentages
    #
    # === Return
    # (Hash):: Converted values with keys "total" and "percent" with latter being a hash with values as percentages
    def percentage(values)
      total = 0
      values.each_value { |v| total += v }
      percent = {}
      values.each { |k, v| percent[k] = (v / total.to_f) * 100.0 } if total > 0
      {"percent" => percent, "total" => total}
    end

    def self.percentage(values)
      total = 0
      values.each_value { |v| total += v }
      percent = {}
      values.each { |k, v| percent[k] = (v / total.to_f) * 100.0 } if total > 0
      {"percent" => percent, "total" => total}
    end

    # Converts server statistics to a displayable format
    #
    # === Parameters
    # stats(Hash):: Statistics with generic keys "identity", "hostname", "service uptime",
    #   "machine uptime", "stat time", "last reset time", "version", and "broker" with the
    #   latter two and "machine uptime" being optional; any other keys ending with "stats"
    #   have an associated hash value that is displayed in sorted key order
    #
    # === Return
    # (String):: Display string
    def stats_str(stats)
      name_width = MAX_STAT_NAME_WIDTH
      str = sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "identity", stats["identity"]) +
            sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "hostname", stats["hostname"]) +
            sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "stat time", time_at(stats["stat time"])) +
            sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "last reset", time_at(stats["last reset time"])) +
            sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "service up", elapsed(stats["service uptime"]))
      str += sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "machine up", elapsed(stats["machine uptime"])) if stats.has_key?("machine uptime")
      str += sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "version", stats["version"].to_i) if stats.has_key?("version")
      str += brokers_str(stats["brokers"], name_width) if stats.has_key?("brokers")
      stats.to_a.sort.each { |k, v| str += sub_stats_str(k[0..-7], v, name_width) if k.to_s =~ /stats$/ }
      str
    end

    # Convert broker information to displayable format
    #
    # === Parameter
    # brokers(Hash):: Broker stats with keys
    #   "brokers"(Array):: Stats for each broker in priority order as hash with keys
    #     "alias"(String):: Broker alias
    #     "identity"(String):: Broker identity
    #     "status"(Symbol):: Status of connection
    #     "disconnect last"(Hash|nil):: Last disconnect information with key "elapsed", or nil if none
    #     "disconnects"(Integer|nil):: Number of times lost connection, or nil if none
    #     "failure last"(Hash|nil):: Last connect failure information with key "elapsed", or nil if none
    #     "failures"(Integer|nil):: Number of failed attempts to connect to broker, or nil if none
    #     "retries"(Integer|nil):: Number of attempts to connect after failure, or nil if none
    #   "exceptions"(Hash|nil):: Exceptions raised per category, or nil if none
    #     "total"(Integer):: Total exceptions for this category
    #     "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    #   "returns"(Hash|nil):: Message return activity stats with keys "total", "percent", "last", and "rate"
    #     with percentage breakdown per request type, or nil if none
    # name_width(Integer):: Fixed width for left-justified name display
    #
    # === Return
    # str(String):: Broker display with one line per broker plus exceptions
    def brokers_str(brokers, name_width)
      value_indent = " " * (name_width + SEPARATOR.size)
      sub_name_width = MAX_SUB_STAT_NAME_WIDTH
      sub_value_indent = " " * (name_width + sub_name_width + (SEPARATOR.size * 2))
      str = sprintf("%-#{name_width}s#{SEPARATOR}", "brokers")
      brokers["brokers"].each do |b|
        disconnects = if b["disconnects"]
          "#{b["disconnects"]} (#{elapsed(b["disconnect last"]["elapsed"])} ago)"
        else
          "none"
        end
        failures = if b["failures"]
          retries = b["retries"]
          retries = " w/ #{retries} #{retries != 1 ? 'retries' : 'retry'}" if retries
          "#{b["failures"]} (#{elapsed(b["failure last"]["elapsed"])} ago#{retries})"
        else
          "none"
        end
        str += "#{b["alias"]}: #{b["identity"]} #{b["status"]}, disconnects: #{disconnects}, failures: #{failures}\n"
        str += value_indent
      end
      str += sprintf("%-#{sub_name_width}s#{SEPARATOR}", "exceptions")
      str += if brokers["exceptions"].nil? || brokers["exceptions"].empty?
        "none\n"
      else
        exceptions_str(brokers["exceptions"], sub_value_indent) + "\n"
      end
      str += value_indent
      str += sprintf("%-#{sub_name_width}s#{SEPARATOR}", "returns")
      str += if brokers["returns"].nil? || brokers["returns"].empty?
        "none\n"
      else
        wrap(activity_str(brokers["returns"]), MAX_SUB_STAT_VALUE_WIDTH, sub_value_indent, ", ") + "\n"
      end
    end

    # Convert grouped set of statistics to displayable format
    # Provide special formatting for stats named "exceptions"
    # Break out percentages and total count for stats containing "percent" hash value
    # sorted in descending percent order and followed by total count
    # Convert to elapsed time for stats with name ending in "last"
    # Add "/sec" to values with name ending in "rate"
    # Add " sec" to values with name ending in "time"
    # Add "%" to values with name ending in "percent" and drop "percent" from name
    # Use elapsed time formatting for values with name ending in "age"
    # Display any nil value, empty hash, or hash with a "total" value of 0 as "none"
    # Display any floating point value or hash of values with at least two significant digits of precision
    #
    # === Parameters
    # name(String):: Display name for the stat
    # value(Object):: Value of this stat
    # name_width(Integer):: Fixed width for left-justified name display
    #
    # === Return
    # (String):: Single line display of stat
    def sub_stats_str(name, value, name_width)
      value_indent = " " * (name_width + SEPARATOR.size)
      sub_name_width = MAX_SUB_STAT_NAME_WIDTH
      sub_value_indent = " " * (name_width + sub_name_width + (SEPARATOR.size * 2))
      sprintf("%-#{name_width}s#{SEPARATOR}", name) + value.to_a.sort.map do |attr|
        k, v = attr
        name = k =~ /percent$/ ? k[0..-9] : k
        sprintf("%-#{sub_name_width}s#{SEPARATOR}", name) + if v.is_a?(Float) || v.is_a?(Integer)
          str = k =~ /age$/ ? elapsed(v) : enough_precision(v)
          str += "/sec" if k =~ /rate$/
          str += " sec" if k =~ /time$/
          str += "%" if k =~ /percent$/
          str
        elsif v.is_a?(Hash)
          if v.empty? || v["total"] == 0
            "none"
          elsif v["total"]
            wrap(activity_str(v), MAX_SUB_STAT_VALUE_WIDTH, sub_value_indent, ", ")
          elsif k =~ /last$/
            last_activity_str(v)
          elsif k == "exceptions"
            exceptions_str(v, sub_value_indent)
          else
            wrap(hash_str(v), MAX_SUB_STAT_VALUE_WIDTH, sub_value_indent, ", ")
          end
        else
          "#{v || "none"}"
        end + "\n"
      end.join(value_indent)
    end

    # Convert activity information to displayable format
    #
    # === Parameters
    # value(Hash|nil):: Information about activity, or nil if the total is 0
    #   "total"(Integer):: Total activity count
    #   "percent"(Hash):: Percentage for each type of activity if tracking type, otherwise omitted
    #   "last"(Hash):: Information about last activity
    #     "elapsed"(Integer):: Seconds since last activity started
    #     "type"(String):: Type of activity if tracking type, otherwise omitted
    #     "active"(Boolean):: Whether activity still active if tracking whether active, otherwise omitted
    #   "rate"(Float):: Recent average rate if measuring rate, otherwise omitted
    #   "duration"(Float):: Average duration of activity if tracking duration, otherwise omitted
    #
    # === Return
    # str(String):: Activity stats in displayable format without any line separators
    def activity_str(value)
      str = ""
      str += enough_precision(sort_value(value["percent"]).reverse).map { |k, v| "#{k}: #{v}%" }.join(", ") +
             ", total: " if value["percent"]
      str += "#{value['total']}"
      str += ", last: #{last_activity_str(value['last'], single_item = true)}" if value["last"]
      str += ", rate: #{enough_precision(value['rate'])}/sec" if value["rate"]
      str += ", duration: #{enough_precision(value['duration'])} sec" if value["duration"]
      str
    end

    # Convert last activity information to displayable format
    #
    # === Parameters
    # last(Hash):: Information about last activity
    #   "elapsed"(Integer):: Seconds since last activity started
    #   "type"(String):: Type of activity if tracking type, otherwise omitted
    #   "active"(Boolean):: Whether activity still active if tracking whether active, otherwise omitted
    # single_item:: Whether this is to appear as a single item in a comma-separated list
    #   in which case there should be no ':' in the formatted string
    #
    # === Return
    # str(String):: Last activity in displayable format without any line separators
    def last_activity_str(last, single_item = false)
      str = "#{elapsed(last['elapsed'])} ago"
      str += " and still active" if last["active"]
      if last["type"]
        if single_item
          str = "#{last['type']} (#{str})"
        else
          str = "#{last['type']}: #{str}"
        end
      end
      str
    end

    # Convert exception information to displayable format
    #
    # === Parameters
    # exceptions(Hash):: Exceptions raised per category
    #   "total"(Integer):: Total exceptions for this category
    #   "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    # indent(String):: Indentation for each line
    #
    # === Return
    # (String):: Exceptions in displayable format with line separators
    def exceptions_str(exceptions, indent)
      indent2 = indent + (" " * 4)
      exceptions.to_a.sort.map do |k, v|
        sprintf("%s total: %d, most recent:\n", k, v["total"]) + v["recent"].reverse.map do |e|
          message = e["message"]
          if message && message.size > (MAX_EXCEPTION_MESSAGE_WIDTH - 3)
            message = e["message"][0, MAX_EXCEPTION_MESSAGE_WIDTH - 3] + "..."
          end
          indent + "(#{e["count"]}) #{time_at(e["when"])} #{e["type"]}: #{message}\n" + indent2 + "#{e["where"]}"
        end.join("\n")
      end.join("\n" + indent)
    end

    # Convert arbitrary nested hash to displayable format
    # Sort hash by key, numerically if possible, otherwise as is
    # Display any floating point values with one decimal place precision
    # Display any empty values as "none"
    #
    # === Parameters
    # hash(Hash):: Hash to be displayed
    #
    # === Return
    # (String):: Single line hash display
    def hash_str(hash)
      str = ""
      sort_key(hash).map do |k, v|
        "#{k}: " + if v.is_a?(Float)
          enough_precision(v)
        elsif v.is_a?(Hash)
          "[ " + hash_str(v) + " ]"
        else
          "#{v || "none"}"
        end
      end.join(", ")
    end

    # Sort hash elements by key in ascending order into array of key/value pairs
    # Sort keys numerically if possible, otherwise as is
    #
    # === Parameters
    # hash(Hash):: Data to be sorted
    #
    # === Return
    # (Array):: Key/value pairs from hash in key sorted order
    def sort_key(hash)
      hash.to_a.map { |k, v| [k =~ /^\d+$/ ? k.to_i : k, v] }.sort
    end

    # Sort hash elements by value in ascending order into array of key/value pairs
    #
    # === Parameters
    # hash(Hash):: Data to be sorted
    #
    # === Return
    # (Array):: Key/value pairs from hash in value sorted order
    def sort_value(hash)
      hash.to_a.sort { |a, b| a[1] <=> b[1] }
    end

    # Wrap string by breaking it into lines at the specified separator
    #
    # === Parameters
    # string(String):: String to be wrapped
    # max_length(Integer):: Maximum length of a line excluding indentation
    # indent(String):: Indentation for each line
    # separator(String):: Separator at which to make line breaks
    #
    # === Return
    # (String):: Multi-line string
    def wrap(string, max_length, indent, separator)
      all = []
      line = ""
      for l in string.split(separator)
        if (line + l).length >= max_length
          all.push(line)
          line = ""
        end
        line += line == "" ? l : separator + l
      end
      all.push(line).join(separator + "\n" + indent)
    end

    # Format UTC time value
    #
    # === Parameters
    # time(Integer):: Time in seconds in Unix-epoch to be formatted
    #
    # (String):: Formatted time string
    def time_at(time)
      Time.at(time).strftime("%a %b %d %H:%M:%S")
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

    # Determine enough precision for floating point value(s) so that all have
    # at least two significant digits and then convert each value to a decimal digit
    # string of that precision after applying rounding
    # When precision is wide ranging, limit precision of the larger numbers
    #
    # === Parameters
    # value(Float|Array|Hash):: Value(s) to be converted
    #
    # === Return
    # (String|Array|Hash):: Value(s) converted to decimal digit string
    def enough_precision(value)
      scale = [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0]
      enough = lambda { |v| (v >= 10.0   ? 0 :
                            (v >= 1.0    ? 1 :
                            (v >= 0.1    ? 2 :
                            (v >= 0.01   ? 3 :
                            (v >  0.001  ? 4 :
                            (v >  0.0    ? 5 : 0)))))) }
      digit_str = lambda { |p, v| sprintf("%.#{p}f", (v * scale[p]).round / scale[p])}

      if value.is_a?(Float)
        digit_str.call(enough.call(value), value)
      elsif value.is_a?(Array)
        min, max = value.map { |_, v| enough.call(v) }.minmax
        precision = (max - min) > 1 ? min + 1 : max
        value.map { |k, v| [k, digit_str.call([precision, enough.call(v)].max, v)] }
      elsif value.is_a?(Hash)
        min, max = value.to_a.map { |_, v| enough.call(v) }.minmax
        precision = (max - min) > 1 ? min + 1 : max
        value.to_a.inject({}) { |s, v| s[v[0]] = digit_str.call([precision, enough.call(v[1])].max, v[1]); s }
      else
        value.to_s
      end
    end

  end # StatsHelper

end # RightScale