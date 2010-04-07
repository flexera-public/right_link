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

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?
  
  require 'fileutils'

  describe RightScale::PowershellHost do
      
    before(:each) do
      flexmock(RightScale::Windows::PowershellPipeServer).new_instances.should_receive(:start).and_return(true)
      flexmock(RightScale::Windows::PowershellPipeServer).new_instances.should_receive(:stop).and_return(true)
      flexmock(RightScale).should_receive(:popen3).and_return(true)
      @host = RightScale::PowershellHost.new(:chef_node=>flexmock('Node'), :provider_name => "PowershellTest" )
      @pipe_server = @host.instance_variable_get(:@pipe_server)
      @response_event = @host.instance_variable_get(:@response_event)
    end
      
    it "should handle is_ready queries" do
      begin
        Thread.new { @host.__send__(:run_command, 'fourty-two') }
        success = false
        10.times do
          success = @pipe_server.request_query(42)
          break if !success.nil?
          sleep 0.1
        end
        success.should be_true
      ensure
        @response_event.signal
      end
    end

    it "should handle respond queries" do
      begin
        Thread.new { @host.__send__(:run_command, 'fourty-two') }
        success = false
        10.times do
          success = @pipe_server.request_query(42)
          break if !success.nil?
          sleep 0.1
        end
        success.should be_true
        res = @pipe_server.request_handler(JSON.dump({RightScale::Windows::PowershellPipeServer::LAST_EXIT_CODE_KEY => 42}))
        res.should == JSON.dump({ :NextAction => 'fourty-two' }) + "\n"
      ensure
        @response_event.signal
      end
    end

    it "should handle multiple respond queries" do
      begin
        Thread.new { @host.__send__(:run_command, 'fourty-two'); @host.__send__(:run_command, 'fourty-three') }

        success = false
        10.times do
          success = @pipe_server.request_query(42)
          break if !success.nil?
          sleep 0.1
        end
        success.should be_true
        res = @pipe_server.request_handler(JSON.dump({RightScale::Windows::PowershellPipeServer::LAST_EXIT_CODE_KEY => 42}))
        res.should == JSON.dump({ :NextAction => 'fourty-two' }) + "\n"
        @response_event.signal

        success = false
        10.times do
          success = @pipe_server.request_query(43)
          break if !success.nil?
          sleep 0.1
        end
        success.should be_true
        res = @pipe_server.request_handler(JSON.dump({RightScale::Windows::PowershellPipeServer::LAST_EXIT_CODE_KEY => 43}))
        res.should == JSON.dump({ :NextAction => 'fourty-three' }) + "\n"
        @response_event.signal
      end
    end

  end

end
