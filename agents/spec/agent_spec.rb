require File.join(File.dirname(__FILE__), '..', '..', 'spec', 'spec_helper')

describe RightScale::Agent do

  describe "Default Option" do

    before(:all) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(AMQP).should_receive(:connect)
      @fanout = flexmock("fanout", :publish => nil)
      @queue = flexmock("queue", :subscribe => {})
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      @agent = RightScale::Agent.start
    end

    it "for daemonize is false" do
      @agent.options.should include(:daemonize)
      @agent.options[:daemonize].should == false
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

  end

  describe "Passed in Options" do

    before(:each) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(AMQP).should_receive(:connect)
      @fanout = flexmock("fanout", :publish => nil)
      @queue = flexmock("queue", :subscribe => {})
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
      flexmock(MQ).should_receive(:new).and_return(@amq)
    end

    # TODO figure out how to stub call to daemonize
    # it "for daemonize should override default (false)" do
    #   agent = RightScale::Agent.start(:daemonize => true)
    #   agent.options.should include(:daemonize)
    #   agent.options[:daemonize].should == true
    # end

    it "for format should override default (marshal)" do
      agent = RightScale::Agent.start(:format => :json)
      agent.options.should include(:format)
      agent.options[:format].should == :json
    end

    # TODO figure out how to avoid console output
    # it "for console should override default (false)" do
    #   agent = RightScale::Agent.start(:console => true)
    #   agent.options.should include(:console)
    #   agent.options[:console].should == true
    # end

    it "for user should override default (nanite)" do
      agent = RightScale::Agent.start(:user => "me")
      agent.options.should include(:user)
      agent.options[:user].should == "me"
    end

    it "for pass(word) should override default (testing)" do
      agent = RightScale::Agent.start(:pass => "secret")
      agent.options.should include(:pass)
      agent.options[:pass].should == "secret"
    end

    it "for secure should override default (false)" do
      agent = RightScale::Agent.start(:secure => true)
      agent.options.should include(:secure)
      agent.options[:secure].should == true
    end

    it "for host should override default (0.0.0.0)" do
      agent = RightScale::Agent.start(:host => "127.0.0.1")
      agent.options.should include(:host)
      agent.options[:host].should == "127.0.0.1"
    end

    it "for log_level should override default (info)" do
      agent = RightScale::Agent.start(:log_level => :debug)
      agent.options.should include(:log_level)
      agent.options[:log_level].should == :debug
    end

    it "for vhost should override default (/nanite)" do
      agent = RightScale::Agent.start(:vhost => "/virtual_host")
      agent.options.should include(:vhost)
      agent.options[:vhost].should == "/virtual_host"
    end

    it "for ping_time should override default (15)" do
      agent = RightScale::Agent.start(:ping_time => 5)
      agent.options.should include(:ping_time)
      agent.options[:ping_time].should == 5
    end

    it "for default_services should override default ([])" do
      agent = RightScale::Agent.start(:default_services => [:test])
      agent.options.should include(:default_services)
      agent.options[:default_services].should == [:test]
    end

    it "for root should override default (#{File.expand_path(File.join(File.dirname(__FILE__), '..'))})" do
      agent = RightScale::Agent.start(:root => File.expand_path(File.dirname(__FILE__)))
      agent.options.should include(:root)
      agent.options[:root].should == File.expand_path(File.dirname(__FILE__))
    end

    it "for file_root should override default (#{File.expand_path(File.join(File.dirname(__FILE__), '..', 'files'))})" do
      agent = RightScale::Agent.start(:file_root => File.expand_path(File.dirname(__FILE__)))
      agent.options.should include(:file_root)
      agent.options[:file_root].should == File.expand_path(File.dirname(__FILE__))
    end

    it "for a single tag should result in the agent's tags being set" do
      agent = RightScale::Agent.start(:tag => "sample_tag")
      agent.tags.should include("sample_tag")
    end

    it "for multiple tags should result in the agent's tags being set" do
      agent = RightScale::Agent.start(:tag => ["sample_tag_1", "sample_tag_2"])
      agent.tags.should include("sample_tag_1")
      agent.tags.should include("sample_tag_2")
    end
    
    it "for threadpool_size" do
      agent = RightScale::Agent.start(:threadpool_size => 5)
      agent.dispatcher.evmclass.threadpool_size.should == 5
    end
    
  end
  
  describe "Security" do

    before(:each) do
      flexmock(EM).should_receive(:add_periodic_timer)
      flexmock(AMQP).should_receive(:connect)
      @fanout = flexmock("fanout", :publish => nil)
      @queue = flexmock("queue", :subscribe => {}, :publish => {})
      @amq = flexmock("AMQueue", :queue => @queue, :fanout => @fanout)
      flexmock(MQ).should_receive(:new).and_return(@amq)
      serializer = RightScale::Serializer.new
      @request = RightScale::RequestPacket.new('/foo/bar', '')
      @push = RightScale::PushPacket.new('/foo/bar', '')
      @agent = RightScale::Agent.start
    end
    
    it 'should correctly deny requests' do
      security = flexmock("Security")
      @agent.register_security(security)
      
      security.should_receive(:authorize).twice.and_return(false)
      flexmock(@agent.dispatcher).should_receive(:dispatch).never
      @agent.__send__(:receive, @request)
      @agent.__send__(:receive, @push)
    end

    it 'should correctly authorize requests' do
      security = flexmock("Security")
      @agent.register_security(security)
      
      security.should_receive(:authorize).twice.and_return(true)
      flexmock(@agent.dispatcher).should_receive(:dispatch).twice
      @agent.__send__(:receive, @request)
      @agent.__send__(:receive, @push)
    end

    it 'should be ignored when not specified' do
      flexmock(@agent.dispatcher).should_receive(:dispatch).twice
      @agent.__send__(:receive, @request)
      @agent.__send__(:receive, @push)
    end    

  end

end
