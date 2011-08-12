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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'lib', 'chef', 'windows', 'powershell_pipe_server'))
require 'eventmachine'

unless 4 == ARGV.size && ARGV[0] == "-pn" && ARGV[2] == "-na"
  puts "Usage: -pn <pipe name> -na <next action file path>"
  puts
  puts "The <pipe name> is any legal file name which uniquely distinguishes the pipe server."
  puts "The <next action file path> is a text file containing a list of actions to execute in PowerShell."
  exit
end

queue = Queue.new
pipe_name = ARGV[1]
File.open(ARGV[3], "r") do |f|
  while (next_action = f.gets)
    queue.push(next_action) if next_action.chomp!.length > 0
  end
end
done = false

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

EM.run do
  EM.defer do
    powershell_pipe_server = ::RightScale::Windows::PowershellPipeServer.new(:pipe_name => pipe_name) do |action, request|
      case action
      when :is_ready then !queue.empty?
      when :respond then queue.pop
      end
    end
    powershell_pipe_server.start
    puts "Hit Ctrl+C to cancel server"
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

exit 0  # prevents Test::Unit from displaying strange usage help text
