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

      # Number of samples included in calculating average recent activity
      RECENT_SIZE = 10

      # (Integer) Total number of actions
      attr_reader :total

      # (Hash) Number of actions per type
      attr_reader :count_per_type

      # Initialize activity data
      #
      # === Parameters
      # measure_rate(Boolean):: Whether to measure activity rate
      def initialize(measure_rate = true)
        @measure_rate = measure_rate
        @interval = 0.0
        @last_start_time = Time.now
        @avg_duration = 0.0
        @total = 0
        @count_per_type = {}
        @last_type = nil
        @last_id = nil
      end

      # Mark the start of an action and update counts and average rate
      # with weighting toward recent activity
      # Ignore the update if its type contains "stats"
      #
      # === Parameters
      # type(String|Symbol):: Type of action, defaults to nil
      # id(String):: Unique identifier associated with this action
      #
      # === Return
      # now(Time):: Update time
      def update(type = nil, id = nil)
        now = Time.now
        if type.nil? || !(type =~ /stats/)
          @interval = ((@interval * (RECENT_SIZE - 1)) + (now - @last_start_time)) / RECENT_SIZE if @measure_rate
          @last_start_time = now
          @total += 1
          @count_per_type[type] = (@count_per_type[type] || 0) + 1 if type
          @last_type = type
          @last_id = id
        end
        now
      end

      # Mark the finish of an action and update the average duration
      #
      # === Parameters
      # start_time(Time):: Time when action started, defaults to last time start was called
      # id(String):: Unique identifier associated with this action
      #
      # === Return
      # now(Time):: Finish time
      def finish(start_time = nil, id = nil)
        now = Time.now
        start_time ||= @last_start_time
        @avg_duration = ((@avg_duration * (RECENT_SIZE - 1)) + (now - start_time)) / RECENT_SIZE
        @last_id = 0 if id && id == @last_id
        now
      end

      # Convert average interval to average rate
      #
      # === Return
      # (Float|nil):: Recent average rate, or nil if total is 0
      def avg_rate
        if total > 0
          if @interval == 0.0 then 0.0 else 1.0 / @interval end
        end
      end


      # Get average duration of actions
      #
      # === Return
      # (Float|nil) Average duration in seconds of action weighted toward recent activity, or nil if total is 0
      def avg_duration
        @avg_duration if total > 0
      end

      # Get stats about last action
      #
      # === Return
      # (Hash|nil):: Information about last action, or nil if the total is 0
      #   "elapsed"(Integer):: Seconds since last action started
      #   "type"(String):: Type of action if specified, otherwise omitted
      #   "active"(Boolean):: Whether action still active
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
      # (Hash):: Converted data with keys "total" and "percent" with latter being a hash of percentage per type
      def percentage
        percent = {}
        @count_per_type.each { |k, v| percent[k] = (v / @total.to_f) * 100.0 } if @total > 0
        {"percent" => percent, "total" => @total}
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
        @stats = {}
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
            sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "stat time", Time.at(stats["stat time"])) +
            sprintf("%-#{name_width}s#{SEPARATOR}%s\n", "last reset", Time.at(stats["last reset time"])) +
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
    #   "exceptions"(Hash):: Exceptions raised per category with keys
    #     "total"(Integer):: Total exceptions for this category
    #     "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
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
          "#{b["failures"]} (#{elapsed(b["failure last"]["elapsed"])} ago" + (b["retries"] ? " w/ #{b["retries"]} retries)" : ")")
        else
          "none"
        end
        str += "#{b["alias"]}: #{b["identity"]} #{b["status"]}, disconnects: #{disconnects}, failures: #{failures}\n"
        str += value_indent
      end
      str += sprintf("%-#{sub_name_width}s#{SEPARATOR}", "exceptions")
      str += if brokers["exceptions"].empty?
        "none\n"
      else
        exceptions_str(brokers["exceptions"], sub_value_indent) + "\n"
      end
    end

    # Convert grouped set of statistics to displayable format
    # Provide special formatting for stats named "exceptions"
    # Break out percentages and total count for stats containing "percent" hash value
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
          elsif v["percent"]
            str = sort(enough_precision(v["percent"])).map { |k2, v2| "#{k2}: #{v2}%" }.join(", ")
            str += ", total: #{v["total"]}"
            wrap(str, MAX_SUB_STAT_VALUE_WIDTH, sub_value_indent, ", ")
          elsif k =~ /last$/
            str = ""
            str = "#{v["type"]}: " if v["type"]
            str += "#{elapsed(v["elapsed"])} ago"
            str += " and still active" if v["active"]
            str
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

    # Convert exception information to displayable format
    #
    # === Parameters
    # exceptions(Hash):: Exceptions raised per category
    #   "total"(Integer):: Total exceptions for this category
    #   "recent"(Array):: Most recent as a hash of "count", "type", "message", "when", and "where"
    # indent(String):: Indentation for each line
    #
    # === Return
    # (String):: Exception display with one line per exception
    def exceptions_str(exceptions, indent)
      indent2 = indent + (" " * 4)
      exceptions.to_a.sort.map do |k, v|
        sprintf("%s total: %d, most recent:\n", k, v["total"]) + v["recent"].reverse.map do |e|
          message = e["message"]
          if message && message.size > MAX_EXCEPTION_MESSAGE_WIDTH
            message = e["message"][0..MAX_EXCEPTION_MESSAGE_WIDTH] + "..."
          end
          indent + "(#{e["count"]}) #{Time.at(e["when"])} #{e["type"]}: #{message}\n" + indent2 + "#{e["where"]}"
        end.join("\n")
      end.join("\n" + indent)
    end

    # Convert arbitrary nested hash to displayable format
    # Sort hash entries, numerically if possible, otherwise alphabetically
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
      sort(hash).map do |k, v|
        "#{k}: " + if v.is_a?(Float)
          enough_precision(v)
        elsif v.is_a?(Hash)
          "[ " + hash_str(v) + " ]"
        else
          "#{v || "none"}"
        end
      end.join(", ")
    end

    # Sort hash elements into array of key/value pairs
    # Sort keys numerically if possible, otherwise alphabetically
    #
    # === Parameters
    # hash(Hash):: Data to be sorted
    #
    # === Return
    # (Array):: Key/value pairs from hash in key sorted order
    def sort(hash)
      hash.to_a.map { |k, v| [k =~ /^\d+$/ ? k.to_i : k, v] }.sort
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
        "#{minutes} min, #{seconds} sec"
      elsif time <= DAY
        hours = time / HOUR
        minutes = (time - (hours * HOUR)) / MINUTE
        "#{hours} hr, #{minutes} min"
      else
        days = time / DAY
        hours = (time - (days * DAY)) / HOUR
        minutes = (time - (days * DAY) - (hours * HOUR)) / MINUTE
        "#{days} day#{'s' if days != 1}, #{hours} hr, #{minutes} min"
      end
    end

    # Determine enough precision for floating point value(s) so that all have
    # at least two significant digits and then convert each value to a decimal digit
    # string of that precision after applying rounding
    # When precision is wide ranging, limit precision of the larger numbers
    #
    # === Parameters
    # value(Float|Hash):: Value(s) to be converted
    #
    # === Return
    # (String|Hash):: Value(s) converted to decimal digit string
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