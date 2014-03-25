#--
# Copyright (c) 2014 RightScale Inc
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
#++

require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

# Mock RestClient::Response
class RestResponseMock
  attr_reader :headers

  def initialize(headers)
    @headers = headers || {}
  end
end

# Mock RestClient::MovedPermanently exceptions since cannot create directly without a
# RestClient::Response, but need RestClient interface for error handling
class RestMovedPermanentlyMock < RestClient::MovedPermanently
  attr_reader :http_code, :http_body, :response, :message

  def initialize(response_headers = nil)
    @message = "#{301} #{RestClient::STATUSES[301]}"
    @http_code = 301
    @http_body = "moved permanently test"
    @response = RestResponseMock.new(response_headers)
  end
end

# Mock RestClient::Found exceptions since cannot create directly without a
# RestClient::Response, but need RestClient interface for error handling
class RestFoundMock < RestClient::Found
  attr_reader :http_code, :http_body, :response, :message

  def initialize(response_headers = nil)
    @message = "#{302} #{RestClient::STATUSES[302]}"
    @http_code = 302
    @http_body = "found test"
    @response = RestResponseMock.new(response_headers)
  end
end

describe RightScale::InstanceAuthClient do

  include FlexMock::ArgumentTypes

  before(:each) do
    @log = flexmock(RightScale::Log)
    @log.should_receive(:error).by_default.and_return { |m| raise RightScale::Log.format(*m) }
    @log.should_receive(:warning).by_default.and_return { |m| raise RightScale::Log.format(*m) }
    @renew_timer = flexmock("renew timer")
    flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).by_default
    @reconnect_timer = flexmock("reconnect timer")
    flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@reconnect_timer).by_default
    @token_id = 111
    token = "secret"
    public_token = RightScale::SecureIdentity.derive(@token_id, token)
    @identity = RightScale::AgentIdentity.new("rs", "instance", @token_id, public_token).to_s
    @account_id = 123
    @shard_id = 1
    @mode = :http
    @protocol_version = RightScale::AgentConfig.protocol_version
    @right_link_version = RightLink.version
    @api_url = "https://my1.com/api"
    @auth_url = "https://111:secret@my1.com/api"
    @router_url = "https://rn1.com/router"
    @response = {
      "access_token" => "access token",
      "expires_in" => 60,
      "api_url" => @api_url,
      "router_url" => @router_url,
      "shard_id" => @shard_id,
      "mode" => @mode }
    @http_client = flexmock("http client", :post => @response, :check_health => true).by_default
    flexmock(RightScale::BalancedHttpClient).should_receive(:new).and_return(@http_client).by_default
    @not_responding = RightScale::BalancedHttpClient::NotResponding
    @options = {
      :api_url => @api_url,
      :identity => @identity,
      :token => token,
      :account_id => @account_id }
    @client = RightScale::InstanceAuthClient.new(@options)
  end

  context :initialize do
    [:identity, :token, :account_id, :api_url].each do |o|
      it "raises if #{o.inspect} option missing" do
        @options.delete(o)
        lambda { RightScale::InstanceAuthClient.new(@options) }.should raise_error(ArgumentError, "#{o.inspect} option missing")
      end
    end

    it "creates HTTP client" do
      flexmock(RightScale::BalancedHttpClient).should_receive(:new).and_return(@http_client).once
      @client = RightScale::InstanceAuthClient.new(@options)
    end

    it "gets authorized with continuous renewal by default" do
      flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).once
      @client = RightScale::InstanceAuthClient.new(@options)
    end

    it "gets authorized once immediately if :no_renew is specified" do
      flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).never
      @http_client.should_receive(:post).and_return(@response).once
      @client = RightScale::InstanceAuthClient.new(@options.merge(:no_renew => true))
    end
  end

  context :headers do
    it "adds User-Agent header" do
      @client.send(:state=, :authorized)
      @client.headers["User-Agent"].should_not be_nil
    end

    it "adds X-RightLink-ID header" do
      @client.send(:state=, :authorized)
      @client.headers["X-RightLink-ID"].should == @token_id
    end
  end

  context :redirect do
    it "handles redirect by renewing authorization" do
      @log.should_receive(:info).with("Renewing authorization because of request redirect to \"location\"")
      flexmock(@client).should_receive(:renew_authorization).with(0).once
      @client.redirect("location").should be_true
    end
  end

  context :close do
    it "should cancel all timers" do
      @client.send(:reconnect)
      @renew_timer.should_receive(:cancel).once
      @reconnect_timer.should_receive(:cancel).once
      @client.close.should be_true
      @client.instance_variable_get(:@renew_timer).should be_nil
      @client.instance_variable_get(:@reconnect_timer).should be_nil
    end
  end

  context :create_http_client do
    it "creates client with required options" do
      flexmock(RightScale::BalancedHttpClient).should_receive(:new).with(@auth_url, on { |a| a[:api_version] == "1.5" &&
          a[:open_timeout] == 2 && a[:request_timeout] == 5 && a[:non_blocking].nil? }).and_return(@http_client).once
      @client.send(:create_http_client).should == @http_client
    end

    it "enables non-blocking if specified" do
      @client = RightScale::InstanceAuthClient.new(@options.merge(:non_blocking => true))
      flexmock(RightScale::BalancedHttpClient).should_receive(:new).with(@auth_url, on { |a| a[:non_blocking] == true }).and_return(@http_client).once
      @client.send(:create_http_client).should == @http_client
    end
  end

  context :get_authorized do
    before(:each) do
      @http_client.should_receive(:post).and_return(@response).by_default
    end

    it "posts authorization request to API" do
      @http_client.should_receive(:post).with("/oauth2", on { |a| a[:account_id] == @account_id &&
          a[:grant_type] == "client_credentials" && a[:r_s_version] == @protocol_version && a[:right_link_version] == @right_link_version },
          on { |a| a[:headers] == {"User-Agent" => "RightLink v#{@right_link_version}", "X-RightLink-ID" => @token_id} }).and_return(@response).once
      @client.send(:get_authorized).should be_true
    end

    it "sets state to :authorized" do
      @client.send(:get_authorized).should be_true
      @client.state.should == :authorized
    end

    it "updates URLs and other data from authorization response" do
      @later = Time.at(@now = Time.now)
      flexmock(Time).should_receive(:now).and_return { @later += 1 }
      @response.merge!(
        "access_token" => "new access token",
        "expires_in" => 3600,
        "api_url" => "https://my2.com/api",
        "router_url" => "https://rn2.com/router",
        "shard_id" => 2,
        "mode" => :http )
      @client.send(:get_authorized).should be_true
      @client.instance_variable_get(:@access_token).should == "new access token"
      @client.instance_variable_get(:@expires_at).should == (@later + 3600)
      @client.api_url.should == "https://my2.com/api"
      @client.shard_id.should == 2
      @client.mode.should == :http
    end

    it "sets state to :unauthorized and raises if authorization fails" do
      @http_client.should_receive(:post).and_raise(RestClient::Unauthorized)
      lambda { @client.send(:get_authorized) }.should raise_error(RightScale::Exceptions::Unauthorized)
      @client.state.should == :unauthorized
    end

    context "when not responding" do
      it "retries authorization" do
        @http_client.should_receive(:post).and_raise(@not_responding, "out of service").once.ordered
        @http_client.should_receive(:post).and_return(@response).once.ordered
        flexmock(@client).should_receive(:sleep).with(5).once
        @client.send(:get_authorized).should be_true
      end

      it "limits number of retries" do
        @http_client.should_receive(:post).and_raise(@not_responding, "out of service").times(6)
        flexmock(@client).should_receive(:sleep).with(5).times(5)
        @log.should_receive(:error).with("Exceeded maximum authorization retries (5)").once
        lambda { @client.send(:get_authorized) }.should raise_error(@not_responding)
      end
    end

    it "repeatedly redirects if API server tells it to" do
      location = "https://my3.com/api"
      found = RestFoundMock.new(:location => location)
      moved = RestMovedPermanentlyMock.new({:location => location})
      @http_client.should_receive(:post).and_raise(found).once.ordered
      @http_client.should_receive(:post).and_raise(moved).twice.ordered
      flexmock(@client).should_receive(:redirected).with(found).and_return(true).once.ordered
      flexmock(@client).should_receive(:redirected).with(moved).and_return(true).once.ordered
      flexmock(@client).should_receive(:redirected).with(moved).and_return(false).once.ordered
      lambda { @client.send(:get_authorized) }.should raise_error(moved)
    end

    it "limits number of redirects and sets state to :failed when exceeded" do
      location = "https://my3.com/api"
      moved = RestMovedPermanentlyMock.new(:location => location)
      @log.should_receive(:error).with("Exceeded maximum redirects (5)").once
      @http_client.should_receive(:post).and_raise(moved).times(6)
      lambda { @client.send(:get_authorized) }.should raise_error(moved)
      @client.state.should == :failed
    end

    it "restores to original URLs after redirect failure" do
      location = "https://my3.com/api"
      moved = RestMovedPermanentlyMock.new(:location => location)
      @http_client.should_receive(:post).and_raise(moved).times(6)
      @log.should_receive(:error).with("Exceeded maximum redirects (5)").once
      lambda { @client.send(:get_authorized) }.should raise_error(moved)
      @client.instance_variable_get(:@api_url).should == @api_url
    end

    it "sets state to :failed and raises if there is an unexpected exception" do
      @http_client.should_receive(:post).and_raise(RuntimeError, "test").once
      lambda { @client.send(:get_authorized) }.should raise_error(RuntimeError, "test")
      @client.state.should == :failed
    end
  end

  context :renew_authorization do
    before(:each) do
      @http_client.should_receive(:post).and_return(@response).by_default
      @client = RightScale::InstanceAuthClient.new(@options.merge(:no_renew => true))
      @tick = 1
      @later = Time.at(@now = Time.now)
      flexmock(Time).should_receive(:now).and_return { @later += @tick }
    end

    it "gets authorized" do
      flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).and_yield.once.ordered
      flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).once.ordered
      @http_client.should_receive(:post).and_return(@response).once
      @client.send(:renew_authorization).should be_true
    end

    it "renews authorization after half the remaining time has expired" do
      flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@renew_timer).and_yield.once.ordered
      flexmock(EM::Timer).should_receive(:new).with(29, Proc).and_return(@renew_timer).once.ordered
      @client.send(:renew_authorization, 0).should be_true
    end

    it "waits to start authorization renewal" do
      flexmock(EM::Timer).should_receive(:new).with(10, Proc).and_return(@renew_timer).and_yield.once.ordered
      flexmock(EM::Timer).should_receive(:new).with(29, Proc).and_return(@renew_timer).once.ordered
      @client.send(:renew_authorization, 10).should be_true
    end

    it "defaults wait time to half remaining expired time if already authorized" do
      @client.state.should == :authorized
      flexmock(EM::Timer).should_receive(:new).with(29, Proc).and_return(@renew_timer).once
      @client.send(:renew_authorization).should be_true
    end

    it "cancels existing renewal and immediately renews if requested" do
      flexmock(EM::Timer).should_receive(:new).with(30, Proc).and_return(@renew_timer).once.ordered
      @client.send(:renew_authorization, 30)
      @renew_timer.should_receive(:cancel).once
      flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@renew_timer).and_yield.once.ordered
      flexmock(EM::Timer).should_receive(:new).with(29, Proc).and_return(@renew_timer).once.ordered
      @client.send(:renew_authorization, 0).should be_true
    end

    it "does not renew authorization if already doing so" do
      flexmock(EM::Timer).should_receive(:new).with(30, Proc).and_return(@renew_timer).once.ordered
      @client.send(:renew_authorization, 30)
      @renew_timer.should_receive(:cancel).never
      flexmock(EM::Timer).should_receive(:new).never
      @client.send(:renew_authorization, 30).should be_true
    end

    context "when not responding" do
      it "keeps trying to renew in half the remaining time" do
        @http_client.should_receive(:post).and_raise(@not_responding, "out of service").times(7).ordered
        @http_client.should_receive(:post).and_return(@response).once.ordered
        flexmock(@client).should_receive(:sleep).with(5)
        @log.should_receive(:error).with("Exceeded maximum authorization retries (5)").once
        flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(on { |a| a.round == 29 }, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(29, Proc).and_return(@renew_timer).once.ordered
        @client.send(:renew_authorization, 0).should be_true
      end

      it "sets state to :expired and reconnects if have reached minimum renew time" do
        @tick = 10
        @http_client.should_receive(:post).and_raise(@not_responding, "out of service").times(36)
        flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).and_yield.times(6)
        flexmock(@client).should_receive(:reconnect).once
        flexmock(@client).should_receive(:sleep)
        @log.should_receive(:error).with("Exceeded maximum authorization retries (5)")
        @client.send(:renew_authorization, 0).should be_true
        @client.state.should == :expired
      end
    end

    context "when unauthorized" do
      it "uses base renew time if previously authorized" do
        flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(60, Proc).and_return(@renew_timer).once.ordered
        @http_client.should_receive(:post).and_raise(RestClient::Unauthorized).once
        @client.state.should == :authorized
        @client.send(:renew_authorization, 0).should be_true
      end

      it "exponentially increases renew time if previously unauthorized" do
        flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(60, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(120, Proc).and_return(@renew_timer).once.ordered
        @http_client.should_receive(:post).and_raise(RestClient::Unauthorized).twice.ordered
        @client.instance_variable_set(:@state, :unauthorized)
        @client.send(:renew_authorization, 0).should be_true
      end

      it "limits the exponential increase in renew time" do
        flexmock(EM::Timer).should_receive(:new).with(0, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(60, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(120, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(240, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(480, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(960, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(1920, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(3600, Proc).and_return(@renew_timer).and_yield.once.ordered
        flexmock(EM::Timer).should_receive(:new).with(3600, Proc).and_return(@renew_timer).once.ordered
        @http_client.should_receive(:post).and_raise(RestClient::Unauthorized).times(8).ordered
        @client.instance_variable_set(:@state, :unauthorized)
        @client.send(:renew_authorization, 0).should be_true
      end
    end

    it "sets state to :failed and logs error if there is a mode switch" do
      flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).and_yield.once
      flexmock(@client).should_receive(:get_authorized).and_raise(RightScale::InstanceAuthClient::CommunicationModeSwitch).once
      @log.should_receive(:error).with("Failed authorization renewal", RightScale::InstanceAuthClient::CommunicationModeSwitch, :no_trace).once
      @client.send(:renew_authorization).should be_true
      @client.state.should == :failed
    end

    it "sets state to :failed and logs error if there is an unexpected exception" do
      flexmock(EM::Timer).should_receive(:new).and_return(@renew_timer).and_yield.once
      flexmock(@client).should_receive(:get_authorized).and_raise(RuntimeError).once
      @log.should_receive(:error).with("Failed authorization renewal", RuntimeError, :trace).once
      @client.send(:renew_authorization).should be_true
      @client.state.should == :failed
    end
  end

  context :update_urls do
    before(:each) do
      @response = RightScale::SerializationHelper.symbolize_keys(@response)
    end

    it "updates shard ID" do
      @client.instance_variable_get(:@shard_id).should == 1
      @response.merge!(:shard_id => 2)
      @client.send(:update_urls, @response).should be_true
      @client.instance_variable_get(:@shard_id).should == 2
    end

    it "raises CommunicationModeSwitch if mode changes" do
      @client.instance_variable_get(:@mode).should == :http
      @response.merge!(:mode => :amqp)
      lambda { @client.send(:update_urls, @response) }.should raise_error(RightScale::InstanceAuthClient::CommunicationModeSwitch)
    end

    it "updates router URL if it has changed" do
      @client.instance_variable_get(:@router_url).should == "https://rn1.com/router"
      @response.merge!(:router_url => "https://rn2.com/router")
      @client.send(:update_urls, @response).should be_true
      @client.instance_variable_get(:@router_url).should == "https://rn2.com/router"
    end

    it "updates API URL if API URL has changed and recreates HTTP client" do
      @client.instance_variable_get(:@api_url).should == @api_url
      @response.merge!(:api_url => "https://my2.com/api")
      flexmock(RightScale::BalancedHttpClient).should_receive(:new).and_return(@http_client).once
      @client.send(:update_urls, @response).should be_true
      @client.instance_variable_get(:@api_url).should == "https://my2.com/api"
    end
  end

  context :redirected do
    it "updates API URL and authorization URL and recreates HTTP client" do
      location = "https://my3.com/api"
      moved = RestMovedPermanentlyMock.new(:location => location)
      flexmock(RightScale::BalancedHttpClient).should_receive(:new).and_return(@http_client).once
      @log.should_receive(:info).with(/Updating RightApi URL/).once
      @client.send(:redirected, moved).should be_true
      @client.instance_variable_get(:@api_url).should == location
    end

    it "logs error and returns false if there is no redirect location" do
      moved = RestMovedPermanentlyMock.new
      @log.should_receive(:error).with("Redirect exception does contain a redirect location").once
      @client.send(:redirected, moved).should be_false
    end

    it "logs error and returns false if the redirect location is not usable" do
      moved = RestMovedPermanentlyMock.new(:location => "amqp://my3.com/api")
      @log.should_receive(:error).with("Failed redirect because location is invalid: \"amqp://my3.com/api\"").once
      @client.send(:redirected, moved).should be_false
    end
  end

  context :reconnect do
    before(:each) do
      @client.instance_variable_set(:@reconnecting, nil)
    end

    it "waits random interval before reconnecting" do
      flexmock(@client).should_receive(:rand).with(15).and_return(10).once
      flexmock(EM::PeriodicTimer).should_receive(:new).with(10, Proc).and_return(@reconnect_timer).once
      @client.send(:reconnect).should be_true
    end

    context "when health check successful" do
      before(:each) do
        @http_client.should_receive(:check_health).once
        flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@reconnect_timer).and_yield.once
      end

      it "renews authorization" do
        @renew_timer.should_receive(:cancel)
        flexmock(@client).should_receive(:renew_authorization).with(0).once
        @client.send(:reconnect).should be_true
      end

      it "disables timer" do
        @renew_timer.should_receive(:cancel)
        @client.send(:reconnect).should be_true
        @client.instance_variable_get(:@reconnecting).should be_nil
      end
    end

    context "when reconnect fails" do
      before(:each) do
        @later = Time.at(@now = Time.now)
        flexmock(Time).should_receive(:now).and_return { @later += 1 }
        flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@reconnect_timer).and_yield.once
      end

      it "updates stats but does not log if not responding" do
        @log.should_receive(:info).never
        flexmock(@http_client).should_receive(:check_health).and_raise(@not_responding, "out of service").once
        @client.send(:reconnect).should be_true
        stats = @client.instance_variable_get(:@stats)["reconnects"]
        stats.last.should == {"elapsed" => 1, "type" => "no response"}
        stats.total.should == 2
      end

      it "logs error if unexpected exception is raised" do
        flexmock(@http_client).should_receive(:check_health).and_raise(RuntimeError).once
        @log.should_receive(:error).with("Failed authorization reconnect", StandardError).once
        @client.send(:reconnect).should be_true
      end
    end

    it "does nothing if already reconnecting" do
      flexmock(EM::PeriodicTimer).should_receive(:new).and_return(@reconnect_timer).once
      @client.send(:reconnect).should be_true
      @client.instance_variable_get(:@reconnecting).should be_true
      @client.send(:reconnect).should be_true
      @client.instance_variable_get(:@reconnecting).should be_true
    end
  end
end
