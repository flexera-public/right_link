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

require 'fileutils'
require 'tempfile'
require 'thread'
require 'json'

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
      @@mu ||= {}
      @@mu[path] ||= Mutex.new
      mu = @@mu[path]
      mu.synchronize do
        File.open(path, "r:utf-8") do |f|
          return JSON.load(f)
        end
      end
    end

    # Serialize object to JSON and write result to file. Write to a temp file and
    # then copy to keep operations atomic. Have had issues with partially written
    # files before on vScale cloud as its pretty unpredictable what state the 
    # filesystem will be in if you perform a shutdown as it does a disk snapshot
    # a little before the OS has time to fully shut down.
    # Note: Do not serialize object if it's a string, allows passing raw JSON.
    #
    # === Parameters
    # path(String):: Path to file being written
    # contents(Object|String):: Object to be serialized into JSON or JSON string
    #
    # === Return
    # true:: Always return true
    def self.write_json(path, contents)
      @@mu ||= {}
      @@mu[path] ||= Mutex.new
      mu = @@mu[path]
      contents = contents.to_json unless contents.is_a?(String)
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
      filename = Dir::Tmpname.create('rl-foo', dir) { |f| raise Errno::EEXIST if File.exists?(f) }
      begin
        File.open(filename, File::RDWR|File::CREAT) do |f|
          f.write(contents)
          f.close
          mu.synchronize do
            FileUtils.mv(filename, path, :force => true)
          end
        end
      ensure
        # This will be a no-op if the file is successfully moved. Should only
        # trigger if something goes wrong above.
        FileUtils.rm_f(filename)
      end
      true
    end
  end
end
