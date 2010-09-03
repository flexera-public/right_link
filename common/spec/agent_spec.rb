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
require 'tmpdir'

def run_in_em(stop_event_loop = true)
  EM.run do
    yield
    EM.stop_event_loop if stop_event_loop
  end
end

describe RightScale::Agent do

  describe "Default Option" do

    before(:all) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(EM).should_receive(:next_tick).and_yield
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @timer.should_receive(:cancel)
      @broker = flexmock("broker", :subscribe => true, :publish => true, :prefetch => true,
                         :connected => ["b1"], :failed => [], :close_one => true).by_default
      @broker.should_receive(:connection_status).and_yield(:connected)
      flexmock(RightScale::HA_MQ).should_receive(:new).and_return(@broker)
      flexmock(RightScale::PidFile).should_receive(:new).
              and_return(flexmock("pid file", :check=>true, :write=>true, :remove=>true))
      @identity = "rs-instance-123-1"
      @agent = RightScale::Agent.start(:identity => @identity)
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end

    it "for daemonize is false" do
      @agent.options.should include(:daemonize)
      @agent.options[:daemonize].should == false
    end

    it "for shared_queue is false" do
      @agent.options.should include(:shared_queue)
      @agent.options[:shared_queue].should == false
    end

    it "for format is marshal" do
      @agent.options.should include(:format)
      @agent.options[:format].should == :marshal
    end

    it "for console is false" do
      @agent.options.should include(:console)
      @agent.options[:console].should == false
    end

    it "for user is agent" do
      @agent.options.should include(:user)
      @agent.options[:user].should == "agent"
    end

    it "for pass(word) is testing" do
      @agent.options.should include(:pass)
      @agent.options[:pass].should == "testing"
    end

    it "for secure is false" do
      @agent.options.should include(:secure)
      @agent.options[:secure].should == false
    end

    it "for host is localhost" do
      @agent.options.should include(:host)
      @agent.options[:host].should == "localhost"
    end

    it "for log_level is info" do
      @agent.options.should include(:log_level)
      @agent.options[:log_level].should == :info
    end

    it "for vhost is /right_net" do
      @agent.options.should include(:vhost)
      @agent.options[:vhost].should == "/right_net"
    end

    it "for default_services is []" do
      @agent.options.should include(:default_services)
      @agent.options[:default_services].should == []
    end

    it "for root is #{Dir.pwd}" do
      @agent.options.should include(:root)
      @agent.options[:root].should == Dir.pwd
    end

    it "for file_root is #{File.join(Dir.pwd, 'files')}" do
      @agent.options.should include(:file_root)
      @agent.options[:file_root].should == File.join(Dir.pwd, 'files')
    end

  end

  describe "Options from config.yml" do

    before(:all) do
      @agent = RightScale::Agent.start
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end
 
  end

  describe "Passed in Options" do

    before(:each) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(EM).should_receive(:next_tick).and_yield
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer)
      @timer.should_receive(:cancel)
      @broker = flexmock("broker", :subscribe => true, :publish => true, :prefetch => true,
                         :connected => ["b1"], :failed => []).by_default
      @broker.should_receive(:connection_status).and_yield(:connected)
      flexmock(RightScale::HA_MQ).should_receive(:new).and_return(@broker)
      flexmock(RightScale::PidFile).should_receive(:new).
              and_return(flexmock("pid file", :check=>true, :write=>true, :remove=>true))
      @identity = "rs-core-123-1"
      @agent = nil
    end

    after(:each) do
      FileUtils.rm_rf(File.normalize_path(File.join(@agent.options[:root], 'config.yml'))) if @agent
    end

    # TODO figure out how to stub call to daemonize
    # it "for daemonize should override default (false)" do
    #   agent = RightScale::Agent.start(:daemonize => true)
    #   agent.options.should include(:daemonize)
    #   agent.options[:daemonize].should == true
    # end

    it "for format should override default (marshal)" do
      @agent = RightScale::Agent.start(:identity => @identity, :format => :json)
      @agent.options.should include(:format)
      @agent.options[:format].should == :json
    end

    it "for shared_queue should not be included if false" do
      agent = RightScale::Agent.start(:identity => @identity)
      agent.options.should include(:shared_queue)
      agent.options[:shared_queue].should be_false
    end

    it "for shared_queue should be included if not false" do
      agent = RightScale::Agent.start(:shared_queue => "my_shared_queue", :identity => @identity)
      agent.options.should include(:shared_queue)
      agent.options[:shared_queue].should == "my_shared_queue"
    end

    # TODO figure out how to avoid console output
    # it "for console should override default (false)" do
    #   @agent = RightScale::Agent.start(:console => true, :identity => @identity)
    #   @agent.options.should include(:console)
    #   @agent.options[:console].should == true
    # end

    it "for user should override default (agent)" do
      @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
      @agent.options.should include(:user)
      @agent.options[:user].should == "me"
    end

    it "for pass(word) should override default (testing)" do
      @agent = RightScale::Agent.start(:pass => "secret", :identity => @identity)
      @agent.options.should include(:pass)
      @agent.options[:pass].should == "secret"
    end

    it "for secure should override default (false)" do
      @agent = RightScale::Agent.start(:secure => true, :identity => @identity)
      @agent.options.should include(:secure)
      @agent.options[:secure].should == true
    end

    it "for host should override default (localhost)" do
      @agent = RightScale::Agent.start(:host => "127.0.0.1", :identity => @identity)
      @agent.options.should include(:host)
      @agent.options[:host].should == "127.0.0.1"
    end

    it "for log_dir" do
      # testing path, remove it before the test to verify the directory is
      # actually created
      test_log_path = File.normalize_path(File.join(Dir.tmpdir, "right_net", "testing"))
      FileUtils.rm_rf(test_log_path)

      @agent = RightScale::Agent.start(:log_dir => File.normalize_path(File.join(Dir.tmpdir, "right_net", "testing")),
                                       :identity => @identity)

      # passing log_dir will cause log_path to be set to the same value and the
      # directory wil be created
      @agent.options.should include(:log_dir)
      @agent.options[:log_dir].should == test_log_path

      @agent.options.should include(:log_path)
      @agent.options[:log_path].should == test_log_path

      File.directory?(@agent.options[:log_path]).should == true
    end

    it "for log_level should override default (info)" do
      @agent = RightScale::Agent.start(:log_level => :debug, :identity => @identity)
      @agent.options.should include(:log_level)
      @agent.options[:log_level].should == :debug
    end

    it "for vhost should override default (/right_net)" do
      @agent = RightScale::Agent.start(:vhost => "/virtual_host", :identity => @identity)
      @agent.options.should include(:vhost)
      @agent.options[:vhost].should == "/virtual_host"
    end

    it "for ping_time should override default (15)" do
      @agent = RightScale::Agent.start(:ping_time => 5, :identity => @identity)
      @agent.options.should include(:ping_time)
      @agent.options[:ping_time].should == 5
    end

    it "for default_services should override default ([])" do
      @agent = RightScale::Agent.start(:default_services => [:test], :identity => @identity)
      @agent.options.should include(:default_services)
      @agent.options[:default_services].should == [:test]
    end

    it "for root should override default (#{File.normalize_path(File.join(File.dirname(__FILE__), '..'))})" do
      @agent = RightScale::Agent.start(:root => File.normalize_path(File.dirname(__FILE__)),
                                       :identity => @identity)
      @agent.options.should include(:root)
      @agent.options[:root].should == File.normalize_path(File.dirname(__FILE__))
    end

    it "for file_root should override default (#{File.normalize_path(File.join(File.dirname(__FILE__), '..', 'files'))})" do
      @agent = RightScale::Agent.start(:file_root => File.normalize_path(File.dirname(__FILE__)),
                                       :identity => @identity)
      @agent.options.should include(:file_root)
      @agent.options[:file_root].should == File.normalize_path(File.dirname(__FILE__))
    end

    it "for a single tag should result in the agent's tags being set" do
      @agent = RightScale::Agent.start(:tag => "sample_tag", :identity => @identity)
      @agent.tags.should include("sample_tag")
    end

    it "for multiple tags should result in the agent's tags being set" do
      @agent = RightScale::Agent.start(:tag => ["sample_tag_1", "sample_tag_2"], :identity => @identity)
      @agent.tags.should include("sample_tag_1")
      @agent.tags.should include("sample_tag_2")
    end
    
    it "for threadpool_size" do
      @agent = RightScale::Agent.start(:threadpool_size => 5, :identity => @identity)
      @agent.dispatcher.em.threadpool_size.should == 5
    end
    
  end

  describe "Terminating" do

    before(:each) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(EM).should_receive(:next_tick).and_yield
      @timer = flexmock("timer")
      flexmock(EM::Timer).should_receive(:new).and_return(@timer).by_default
      @timer.should_receive(:cancel).by_default
      @broker = flexmock("broker", :subscribe => true, :publish => true, :prefetch => true,
                         :connected => ["b1"], :failed => [], :unusable => [], :close_one => true).by_default
      @broker.should_receive(:connection_status).and_yield(:connected)
      flexmock(RightScale::HA_MQ).should_receive(:new).and_return(@broker)
      flexmock(RightScale::PidFile).should_receive(:new).
              and_return(flexmock("pid file", :check=>true, :write=>true, :remove=>true))
      @mapper_proxy = flexmock("mapper_proxy")
      flexmock(RightScale::MapperProxy).should_receive(:new).and_return(@mapper_proxy)
      @dispatcher = flexmock("dispatcher")
      flexmock(RightScale::Dispatcher).should_receive(:new).and_return(@dispatcher)
      @identity = "rs-core-123-1"
      @agent = nil
    end

    it "should unregister from mapper" do
      @broker.should_receive(:unsubscribe).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register).once
        @agent.run
        @agent.terminate
      end
    end

    it "should close unusable broker connections at start of termination" do
      @broker.should_receive(:unsubscribe).once
      @broker.should_receive(:unusable).and_return(["rs-broker-123-1"]).once
      @broker.should_receive(:close_one).with("rs-broker-123-1", false).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register).once
        @agent.run
        @agent.terminate
      end
    end

    it "should unsubscribe from shared queue" do
      @broker.should_receive(:unsubscribe).with(["shared"], 15, Proc).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity, :shared_queue => "shared")
        flexmock(@agent).should_receive(:un_register).once
        @agent.run
        @agent.terminate
      end
    end

    it "should wait to terminate if there are recent unfinished requests" do
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
      @mapper_proxy.should_receive(:request_age).and_return(10).once
      @dispatcher.should_receive(:dispatch_age).and_return(nil).once
      @broker.should_receive(:unsubscribe).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should wait to terminate if there are recent dispatches" do
      @mapper_proxy.should_receive(:pending_requests).and_return([]).once
      @mapper_proxy.should_receive(:request_age).and_return(nil).once
      @dispatcher.should_receive(:dispatch_age).and_return(20).and_return(@timer).once
      @broker.should_receive(:unsubscribe).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(10, Proc).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should wait to terminate if there are recent unfinished requests or recent dispatches" do
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
      @mapper_proxy.should_receive(:request_age).and_return(21).once
      @dispatcher.should_receive(:dispatch_age).and_return(22).once
      @broker.should_receive(:unsubscribe).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(9, Proc).and_return(@timer).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should log that terminating and then log the reason for waiting to terminate" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-core-123-1 terminating/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Termination waiting 9 seconds for/).once
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
      @mapper_proxy.should_receive(:request_age).and_return(21).once
      @dispatcher.should_receive(:dispatch_age).and_return(22).once
      @broker.should_receive(:unsubscribe).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(9, Proc).and_return(@timer).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should not log reason for waiting to terminate if no need to wait" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-core-123-1 terminating/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Termination waiting/).never
      @mapper_proxy.should_receive(:pending_requests).and_return([]).once
      @mapper_proxy.should_receive(:request_age).and_return(nil).once
      @dispatcher.should_receive(:dispatch_age).and_return(nil).once
      @broker.should_receive(:unsubscribe).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@timer).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should continue with termination after waiting and log that continuing" do
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Agent rs-core-123-1 terminating/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Termination waiting/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/Continuing with termination/).once
      flexmock(RightScale::RightLinkLog).should_receive(:info).with(/The following 1 request/).once
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).twice
      @mapper_proxy.should_receive(:request_age).and_return(10).twice
      @mapper_proxy.should_receive(:dump_requests).and_return(["request"]).once
      @dispatcher.should_receive(:dispatch_age).and_return(10).once
      @broker.should_receive(:unsubscribe).and_yield.once
      @broker.should_receive(:close).once
      flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).and_yield.once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should execute block after all brokers have been closed" do
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).twice
      @mapper_proxy.should_receive(:request_age).and_return(10).twice
      @mapper_proxy.should_receive(:dump_requests).and_return(["request"]).once
      @dispatcher.should_receive(:dispatch_age).and_return(10).once
      @broker.should_receive(:unsubscribe).and_yield.once
      @broker.should_receive(:close).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).and_yield.once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        called = 0
        @agent.terminate { called += 1 }
        called.should == 1
      end
    end

    it "should stop EM if no block specified" do
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).twice
      @mapper_proxy.should_receive(:request_age).and_return(10).twice
      @mapper_proxy.should_receive(:dump_requests).and_return(["request"]).once
      @dispatcher.should_receive(:dispatch_age).and_return(10).once
      @broker.should_receive(:unsubscribe).and_yield.once
      @broker.should_receive(:close).once
      flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).and_yield.once
      run_in_em(stop_event_loop = false) do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        @agent.terminate
      end
    end

    it "should terminate immediately if called a second time but should still execute block" do
      @mapper_proxy.should_receive(:pending_requests).and_return(["request"]).once
      @mapper_proxy.should_receive(:request_age).and_return(10).once
      @dispatcher.should_receive(:dispatch_age).and_return(10).once
      @broker.should_receive(:unsubscribe).and_yield.once
      flexmock(EM::Timer).should_receive(:new).with(20, Proc).and_return(@timer).once
      @timer.should_receive(:cancel).once
      run_in_em do
        @agent = RightScale::Agent.start(:user => "me", :identity => @identity)
        flexmock(@agent).should_receive(:un_register)
        @agent.run
        called = 0
        @agent.terminate { called += 1 }
        called.should == 0
        @agent.terminate { called += 1 }
        called.should == 1
      end
    end

  end

end
