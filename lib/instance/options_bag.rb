#
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

require 'json'

module RightScale

  # Store agent options in environment variable so child processes
  # can access them too
  class OptionsBag

    # (String) Name of environment variable containing serialized options hash
    OPTIONS_ENV = 'RS_OPTIONS'

    # Store options
    #
    # === Parameters
    # opts(Hash):: Options to be stored, override any options stored earlier
    #
    # === Result
    # opts(Hash):: Options to be stored
    def self.store(opts)
      ENV[OPTIONS_ENV] = JSON.dump(opts)
      opts
    end

    # Load previously stored options (may have been stored in a parent process)
    #
    # === Return
    # opts(Hash):: Previously stored options, empty hash if there is none
    def self.load
      return {} unless serialized = ENV[OPTIONS_ENV]
      begin
        opts = JSON.parser.new(serialized, JSON.load_default_options).parse
        opts = SerializationHelper.symbolize_keys(opts)
      rescue Exception => e
        Log.warning("Failed to deserialize options", e)
        opts = {}
      end
      opts
    end

  end

end

