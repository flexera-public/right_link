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

module RightScale

  module ConsoleHelper
    def self.included(base)
      @@base = base
    end
    
    def start_console
      puts "Starting #{@@base.name.split(":").last.downcase} console (#{self.identity})"
      Thread.new do
        Console.start(self)
      end
    end

  end # ConsoleHelper
  
  module Console
    class << self; attr_accessor :instance; end

    def self.start(binding)
      require 'irb'
      old_args = ARGV.dup
      ARGV.replace ["--simple-prompt"]

      IRB.setup(nil)
      self.instance = IRB::Irb.new(IRB::WorkSpace.new(binding))

      @CONF = IRB.instance_variable_get(:@CONF)
      @CONF[:IRB_RC].call self.instance.context if @CONF[:IRB_RC]
      @CONF[:MAIN_CONTEXT] = self.instance.context

      catch(:IRB_EXIT) { self.instance.eval_input }
    ensure
      ARGV.replace old_args
      # Clean up tty settings in some evil, evil cases
      begin; catch(:IRB_EXIT) { irb_exit }; rescue Exception; end
      # Make agent exit when irb does
      EM.stop if EM.reactor_running?
    end

  end # Console

end # RightScale
