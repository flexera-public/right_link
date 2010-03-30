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

describe RightScale::Agent do

  describe "Default Option" do

    before(:all) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(AMQP).should_receive(:connect)
      @direct = flexmock("direct", :publish => nil)
      @fanout = flexmock("fanout", :publish => nil)
      @bind = flexmock("bind", :subscribe => nil)
      @queue = flexmock("queue", :subscribe => {}, :bind => @bind)
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout, :direct => @direct)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      @agent = RightScale::Agent.start
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

    it "for user is nanite" do
      @agent.options.should include(:user)
      @agent.options[:user].should == "nanite"
    end

    it "for pass(word) is testing" do
      @agent.options.should include(:pass)
      @agent.options[:pass].should == "testing"
    end

    it "for secure is false" do
      @agent.options.should include(:secure)
      @agent.options[:secure].should == false
    end

    it "for host is 0.0.0.0" do
      @agent.options.should include(:host)
      @agent.options[:host].should == "0.0.0.0"
    end

    it "for log_level is info" do
      @agent.options.should include(:log_level)
      @agent.options[:log_level].should == :info
    end

    it "for vhost is /nanite" do
      @agent.options.should include(:vhost)
      @agent.options[:vhost].should == "/nanite"
    end

    it "for ping_time is 15" do
      @agent.options.should include(:ping_time)
      @agent.options[:ping_time].should == 15
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
      flexmock(AMQP).should_receive(:connect)
      @direct = flexmock("direct", :publish => nil)
      @fanout = flexmock("fanout", :publish => nil)
      @bind = flexmock("bind", :subscribe => nil)
      @queue = flexmock("queue", :subscribe => {}, :bind => @bind)
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout, :direct => @direct)
      flexmock(MQ).should_receive(:new).and_return(@amq)
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
      @agent = RightScale::Agent.start(:format => :json)
      @agent.options.should include(:format)
      @agent.options[:format].should == :json
    end

    it "for shared_queue should not be included if false" do
#      @queue = flexmock("queue").should_receive(:subscribe).and_return({}).times(1)
#      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
#      flexmock(MQ).should_receive(:new).and_return(@amq)
      agent = RightScale::Agent.start(:identity => "the_identity")
      agent.options.should include(:shared_queue)
      agent.options[:shared_queue].should be_false
    end

    it "for shared_queue should be included if not false" do
#      @queue = flexmock("queue").should_receive(:subscribe).and_return({}).times(2)
#      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
#      flexmock(MQ).should_receive(:new).and_return(@amq)
      agent = RightScale::Agent.start(:shared_queue => "my_shared_queue")
      agent.options.should include(:shared_queue)
      agent.options[:shared_queue].should == "my_shared_queue"
    end

    # TODO figure out how to avoid console output
    # it "for console should override default (false)" do
    #   @agent = RightScale::Agent.start(:console => true)
    #   @agent.options.should include(:console)
    #   @agent.options[:console].should == true
    # end

    it "for user should override default (nanite)" do
      @agent = RightScale::Agent.start(:user => "me")
      @agent.options.should include(:user)
      @agent.options[:user].should == "me"
    end

    it "for pass(word) should override default (testing)" do
      @agent = RightScale::Agent.start(:pass => "secret")
      @agent.options.should include(:pass)
      @agent.options[:pass].should == "secret"
    end

    it "for secure should override default (false)" do
      @agent = RightScale::Agent.start(:secure => true)
      @agent.options.should include(:secure)
      @agent.options[:secure].should == true
    end

    it "for host should override default (0.0.0.0)" do
      @agent = RightScale::Agent.start(:host => "127.0.0.1")
      @agent.options.should include(:host)
      @agent.options[:host].should == "127.0.0.1"
    end

    it "for log_dir" do
      # testing path, remove it before the test to verify the directory is
      # actually created
      test_log_path = File.normalize_path(File.join(Dir.tmpdir, "right_net", "testing"))
      FileUtils.rm_rf(test_log_path)

      @agent = RightScale::Agent.start(:log_dir => File.normalize_path(File.join(Dir.tmpdir, "right_net", "testing")))

      # passing log_dir will cause log_path to be set to the same value and the
      # directory wil be created
      @agent.options.should include(:log_dir)
      @agent.options[:log_dir].should == test_log_path

      @agent.options.should include(:log_path)
      @agent.options[:log_path].should == test_log_path

      File.directory?(@agent.options[:log_path]).should == true
    end

    it "for log_level should override default (info)" do
      @agent = RightScale::Agent.start(:log_level => :debug)
      @agent.options.should include(:log_level)
      @agent.options[:log_level].should == :debug
    end

    it "for vhost should override default (/nanite)" do
      @agent = RightScale::Agent.start(:vhost => "/virtual_host")
      @agent.options.should include(:vhost)
      @agent.options[:vhost].should == "/virtual_host"
    end

    it "for ping_time should override default (15)" do
      @agent = RightScale::Agent.start(:ping_time => 5)
      @agent.options.should include(:ping_time)
      @agent.options[:ping_time].should == 5
    end

    it "for default_services should override default ([])" do
      @agent = RightScale::Agent.start(:default_services => [:test])
      @agent.options.should include(:default_services)
      @agent.options[:default_services].should == [:test]
    end

    it "for root should override default (#{File.normalize_path(File.join(File.dirname(__FILE__), '..'))})" do
      @agent = RightScale::Agent.start(:root => File.normalize_path(File.dirname(__FILE__)))
      @agent.options.should include(:root)
      @agent.options[:root].should == File.normalize_path(File.dirname(__FILE__))
    end

    it "for file_root should override default (#{File.normalize_path(File.join(File.dirname(__FILE__), '..', 'files'))})" do
      @agent = RightScale::Agent.start(:file_root => File.normalize_path(File.dirname(__FILE__)))
      @agent.options.should include(:file_root)
      @agent.options[:file_root].should == File.normalize_path(File.dirname(__FILE__))
    end

    it "for a single tag should result in the agent's tags being set" do
      @agent = RightScale::Agent.start(:tag => "sample_tag")
      @agent.tags.should include("sample_tag")
    end

    it "for multiple tags should result in the agent's tags being set" do
      @agent = RightScale::Agent.start(:tag => ["sample_tag_1", "sample_tag_2"])
      @agent.tags.should include("sample_tag_1")
      @agent.tags.should include("sample_tag_2")
    end
    
    it "for threadpool_size" do
      @agent = RightScale::Agent.start(:threadpool_size => 5)
      @agent.dispatcher.evmclass.threadpool_size.should == 5
    end
    
  end

end
