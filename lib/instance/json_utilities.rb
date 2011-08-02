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

module RightScale

  # collection of Json utilities
  module JsonUtilities
    # Load JSON from given file
    #
    # === Parameters
    # path(String):: Path to JSON file
    #
    # === Return
    # json(String):: Resulting JSON string
    #
    # === Raise
    # Errno::ENOENT:: Invalid path
    # JSON Exception:: Invalid JSON content
    def self.read_json(path)
      JSON.load(File.read(path))
    end

    # Serialize object to JSON and write result to file, override existing file if any.
    # Note: Do not serialize object if it's a string, allows passing raw JSON.
    #
    # === Parameters
    # path(String):: Path to file being written
    # contents(Object|String):: Object to be serialized into JSON or JSON string
    #
    # === Return
    # true:: Always return true
    def self.write_json(path, contents)
      contents = contents.to_json unless contents.is_a?(String)
      File.open(path, 'w') { |f| f.write(contents) }
      true
    end
  end
end
