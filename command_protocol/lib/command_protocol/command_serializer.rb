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
#

module RightScale

  class CommandSerializer

    # String appended to serialized data to delimit between commands
    SEPARATOR = "\n#GO\n"

    # Serialize given command so it can be sent to command listener
    #
    # === Parameters
    # command(Object):: Command to serialize
    #
    # === Return
    # data(String):: Corresponding serialized data
    def self.dump(command)
      data = YAML::dump(command)
      data += SEPARATOR
    end

    # Deserialize command that was previously serialized with +dump+
    #
    # === Parameters
    # data(String):: String containing serialized data
    #
    # === Return
    # command(Object):: Deserialized command
    #
    # === Raise
    # (RightScale::Exceptions::IO): If serialized data is incorrect
    def self.load(data)
      command = YAML::load(data)
      raise RightScale::Exceptions::IO, "Invalid serialized command:\n#{data}" unless command
      command
    rescue RightScale::Exceptions::IO
      raise
    rescue Exception => e
      raise RightScale::Exceptions::IO, "Invalid serialized command: #{e.message}\n#{data}"
    end
  end
end
