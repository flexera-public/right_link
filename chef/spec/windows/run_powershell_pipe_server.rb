#
# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'lib', 'windows', 'powershell_pipe_server'))
require 'eventmachine'

unless 2 == ARGV.size && ARGV[0] == "-na"
  puts "Usage: -na <nextActionPath>"
  puts
  puts "The nextActionPath is a text file containing a list of actions to execute in powershell."
  exit
end

queue = Queue.new
File.open(ARGV[1], "r") do |f|
  while (next_action = f.gets)
    queue.push(next_action) if next_action.chomp!.length > 0
  end
end
done = false

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

puts "Hit Ctrl+C to cancel server"
EM.run do
  EM.defer do
    powershell_pipe_server = ::RightScale::Windows::PowershellPipeServer.new(:queue => queue, :logger => logger)
    powershell_pipe_server.start
  end
  timer = EM::PeriodicTimer.new(0.1) do
    if done && queue.empty?
      timer.cancel
      EM.stop
    elsif queue.empty?
      queue.push "exit"  # ensure exit command at end of queue
      done = true
    end
  end
end
