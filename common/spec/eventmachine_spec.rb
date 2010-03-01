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

require File.join(File.dirname(__FILE__), 'spec_helper')

describe EventMachine do

  it "should not repeatedly run deferred task if task raises an exception" do
    error = nil
    count = 0
    EM.error_handler { |e| error = e; raise e if (count += 1) > 1 }

    begin
      EM.run do
        EM.add_timer(1) { EM.next_tick { EM.stop } }
        EM.next_tick { raise 'test' }
      end
    rescue Exception => error
      error.should == nil
    end

    EM.error_handler(nil)

    error.class.should == RuntimeError
    error.message.should == 'test'
    count.should == 1
  end

  it "should end EM loop if deferred task raises an exception and there is no error handler" do
    count = 0
    begin
      EM.run do
        EM.add_timer(0) { raise 'test' }
      end
    rescue Exception => error
      error.class.should == RuntimeError
      error.message.should == 'test'
      count += 1
    end
    count.should == 1
  end

end
