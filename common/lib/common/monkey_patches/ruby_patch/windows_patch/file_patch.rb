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

begin
  require 'windows/file'

  class File

    # converts a long path to a short path. in windows terms, this means
    # taking any file/folder name over 8 characters in length and truncating
    # it to 6 characters with ~1..~n appended depending on how many similar
    # names exist in the same directory. file extensions are simply chopped
    # at three letters. the short name is equivalent for all API calls to
    # the long path but requires no special quoting, etc. the path must
    # exist at least partially for the API call to succeed.
    #
    # === Parameters
    # long_path(String):: fully or partially existing long path to be
    # converted to its short path equivalent.
    #
    # === Return
    # short_path(String):: short path equivalent or same path if non-existent
    def self.long_path_to_short_path(long_path)
      if File.exists?(long_path)
        length = 260
        while true
          buffer = 0.chr * length
          length = ::Windows::File::GetShortPathName.call(long_path, buffer, buffer.length)
          if length < buffer.length
            break
          end
        end
        return buffer.unpack('A*').first.gsub("\\", "/")
      else
        # must get short path for any existing ancestor since child doesn't
        # (currently) exist.
        child_name = File.basename(long_path)
        long_parent_path = File.dirname(long_path)

        # note that root dirname is root itself (at least in windows)
        return long_path if long_path == long_parent_path

        # recursion
        short_parent_path = long_path_to_short_path(File.dirname(long_path))
        return File.join(short_parent_path, child_name)
      end
    end

    # First expand the path then shorten the directory.
    # Only shorten the directory and not the file name because 'gem' wants
    # long file names
    def self.normalize_path(file_name, *dir_string)
      path = File.expand_path(file_name, *dir_string)
      dir = self.long_path_to_short_path(File.dirname(path))
      File.join(dir, File.basename(path))
    end

  end

rescue LoadError
  # use the simple definition of normalize_path to avoid breaking code which
  # depends on having this definition.
  class File
    def self.normalize_path(file_name, *dir_string)
      File.expand_path(file_name, *dir_string)
    end
  end

end
