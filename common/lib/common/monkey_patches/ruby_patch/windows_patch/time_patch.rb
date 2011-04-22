#
# Copyright (c) 2011 RightScale Inc
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

require 'rubygems'
require 'windows/time'

# monkey patch Time.now because Windows Ruby interpreters used the wrong API
# and queried local time instead of UTC time prior to Ruby v1.9.1. This
# made the Ruby 1.8.x interpreters vulnerable to external changes to
# timezone which cause Time.now to return times which are offset from from the
# correct value. This implementation is borrowed from the C source for Ruby
# v1.9.1 from www.ruby-lang.org ("win32/win32.c").
if RUBY_VERSION < "1.9.1"
  class Time
    def self.now
      # query UTC time as a 64-bit ularge value.
      filetime = 0.chr * 8
      ::Windows::Time::GetSystemTimeAsFileTime.call(filetime)
      low_date_time = filetime[0,4].unpack('V')[0]
      high_date_time = filetime[4,4].unpack('V')[0]
      value = high_date_time * 0x100000000 + low_date_time

      # value is now 100-nanosec intervals since 1601/01/01 00:00:00 UTC,
      # convert it into UNIX time (since 1970/01/01 00:00:00 UTC).
      value /= 10  # 100-nanoseconds to microseconds
      microseconds = 1000 * 1000
      value -= ((1970 - 1601) * 365.2425).to_i * 24 * 60 * 60 * microseconds
      return Time.at(value / microseconds, value % microseconds)
    end
  end
end
