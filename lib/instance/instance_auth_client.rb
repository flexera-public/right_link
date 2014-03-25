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

module RightScale

  # OAuth2 authorization client for instance agent
  # that continuously renews the authorization
  class InstanceAuthClient < AuthClient

    class CommunicationModeSwitch < RuntimeError; end

    # RightApi API version for use in X-API-Version header
    API_VERSION = "1.5"

    # Default time to wait for HTTP connection to open
    DEFAULT_OPEN_TIMEOUT = 2

    # Default time to wait for response from request, which is chosen to be 5 seconds greater
    # than the response timeout inside the RightNet router
    DEFAULT_REQUEST_TIMEOUT = 5

    # Expiration time divisor for when to renew
    # Multiplier for renewal backoff when unauthorized
    RENEW_FACTOR = 2

    # Minimum expiration time before give up
    MIN_RENEW_TIME = 5

    # Initial interval between renew attempts when unauthorized
    UNAUTHORIZED_RENEW_INTERVAL = 60

    # Maximum interval between renew attempts when unauthorized
    MAX_UNAUTHORIZED_RENEW_INTERVAL = 60 * 60

    # Interval between health checks when disconnected
    HEALTH_CHECK_INTERVAL = 15

    # Maximum redirects allowed for an authorization request
    MAX_REDIRECTS = 5

    # Maximum retries allowed for an authorization request
    MAX_RETRIES = 5

    # Number of seconds between authorization request attempts
    RETRY_INTERVAL = 5

    # ID of shard containing this instance's account
    attr_reader :shard_id

    # Create authorization client for instance agent
    #
    # @option options [Integer] :identity serialized agent identity from which API token ID can be derived
    # @option options [String] :token private to instance agent for authorization with API
    # @option options [Integer] :account_id of account owning this instance agent
    # @option options [String] :api_url for accessing RightApi server for authorization and other services
    # @option options [Symbol] :mode in which communicating with RightNet
    # @option options [Boolean] :no_renew get authorized without setting up for continuous renewal
    # @option options [Boolean] :non_blocking i/o is to be used for HTTP requests by applying
    #   EM::HttpRequest and fibers instead of RestClient; requests remain synchronous
    # @option options [Proc] :exception_callback for unexpected exceptions with following parameters:
    #   [Exception] exception raised
    #   [Packet, NilClass] packet being processed
    #   [Agent, NilClass] agent in which exception occurred
    #
    # @raise [ArgumentError] missing :identity, :token, :account_id, or :api_url
    # @raise [Exceptions::Unauthorized] authorization failed
    # @raise [BalancedHttpClient::NotResponding] cannot access RightApi
    def initialize(options)
      [:identity, :token, :account_id, :api_url].each do |o|
        raise ArgumentError.new("#{o.inspect} option missing") unless options.has_key?(o)
        eval("@#{o} = '#{options[o]}'")
      end
      @token_id = AgentIdentity.parse(@identity).base_id
      @account_id = @account_id.to_i
      @mode = options[:mode] && options[:mode].to_sym
      @router_url = nil
      @other_headers = {"User-Agent" => "RightLink v#{RightLink.version}", "X-RightLink-ID" => @token_id}
      @non_blocking = options[:non_blocking]
      @exception_callback = options[:exception_callback]
      @expires_at = Time.now
      reset_stats
      @state = :pending
      create_http_client
      get_authorized
      renew_authorization unless options[:no_renew]
    end

    # Headers to be added to HTTP request
    #
    # @return [Hash] headers to be added to request header
    #
    # @raise [Exceptions::Unauthorized] not authorized
    # @raise [Exceptions::RetryableError] authorization expired, but retry may succeed
    def headers
      super.merge(@other_headers)
    end

    # An HTTP request received a redirect response
    # Infer from this that need to renew session to get updated URLs
    #
    # @param [String] location to which response indicated to redirect
    #
    # @return [TrueClass] always true
    def redirect(location)
      Log.info("Renewing authorization because of request redirect to #{location.inspect}")
      renew_authorization(0)
      true
    end

    # Take any actions necessary to quiesce client interaction in preparation
    # for agent termination but allow any active requests to complete
    #
    # @return [TrueClass] always true
    def close
      self.state = :closed
      @renew_timer.cancel if @renew_timer
      @renew_timer = nil
      @reconnect_timer.cancel if @reconnect_timer
      @reconnect_timer = nil
      true
    end

    protected

    # Reset statistics for this client
    #
    # @return [TrueClass] always true
    def reset_stats
      super
      @stats["reconnects"] = RightSupport::Stats::Activity.new
      true
    end

    # Create health-checked HTTP client for performing authorization
    #
    # @return [RightSupport::Net::BalancedHttpClient] client
    def create_http_client
      options = {
        :api_version => API_VERSION,
        :open_timeout => DEFAULT_OPEN_TIMEOUT,
        :request_timeout => DEFAULT_REQUEST_TIMEOUT,
        :non_blocking => @non_blocking }
      auth_url = URI.parse(@api_url)
      auth_url.user = @token_id.to_s
      auth_url.password = @token
      @http_client = RightScale::BalancedHttpClient.new(auth_url.to_s, options)
    end

    # Get authorized with RightApi using OAuth2
    # As an extension to OAuth2 receive URLs needed for other servers
    # Retry authorization if RightApi not responding or if get redirected
    #
    # @return [TrueClass] always true
    #
    # @raise [Exceptions::Unauthorized] authorization failed
    # @raise [BalancedHttpClient::NotResponding] cannot access RightApi
    # @raise [CommunicationModeSwitch] changing communication mode
    def get_authorized
      retries = redirects = 0
      api_url = @api_url
      begin
        Log.info("Getting authorized via #{@api_url}")
        params = {
          :grant_type => "client_credentials",
          :account_id => @account_id,
          :r_s_version => AgentConfig.protocol_version,
          :right_link_version => RightLink.version }
        response = @http_client.post("/oauth2", params, :headers => @other_headers)
        response = SerializationHelper.symbolize_keys(response)
        @access_token = response[:access_token]
        @expires_at = Time.now + response[:expires_in]
        update_urls(response)
        self.state = :authorized
        @communicated_callbacks.each { |callback| callback.call } if @communicated_callbacks
      rescue BalancedHttpClient::NotResponding
        if (retries += 1) > MAX_RETRIES
          Log.error("Exceeded maximum authorization retries (#{MAX_RETRIES})")
        else
          sleep(RETRY_INTERVAL)
          retry
        end
        raise
      rescue RestClient::MovedPermanently, RestClient::Found => e
        if (redirects += 1) > MAX_REDIRECTS
          Log.error("Exceeded maximum redirects (#{MAX_REDIRECTS})")
        elsif redirected(e)
          retry
        end
        @api_url = api_url
        raise
      rescue RestClient::Unauthorized => e
        self.state = :unauthorized
        @access_token = nil
        @expires_at = Time.now
        raise Exceptions::Unauthorized.new(e.http_body, e)
      end
      true
    rescue BalancedHttpClient::NotResponding, Exceptions::Unauthorized, CommunicationModeSwitch
      raise
    rescue StandardError => e
      @stats["exceptions"].track("authorize", e)
      self.state = :failed
      raise
    end

    # Get authorized and then continuously renew authorization before it expires
    #
    # @param [Integer, NilClass] wait time before attempt to renew; defaults to
    #   have the expiry time if authorized, otherwise 0
    #
    # @return [TrueClass] always true
    def renew_authorization(wait = nil)
      wait ||= (state == :authorized) ? ((@expires_at - Time.now).to_i / RENEW_FACTOR) : 0

      if @renew_timer && wait == 0
        @renew_timer.cancel
        @renew_timer = nil
      end

      unless @renew_timer
        @renew_timer = EM::Timer.new(wait) do
          @renew_timer = nil
          previous_state = state
          begin
            get_authorized
            renew_authorization
          rescue BalancedHttpClient::NotResponding => e
            if (expires_in = (@expires_at - Time.now).to_i) > MIN_RENEW_TIME
              renew_authorization(expires_in / RENEW_FACTOR)
            else
              self.state = :expired
              reconnect
            end
          rescue Exceptions::Unauthorized => e
            if previous_state == :unauthorized && wait > 0
              renew_authorization([(wait * RENEW_FACTOR), MAX_UNAUTHORIZED_RENEW_INTERVAL].min)
            else
              renew_authorization(UNAUTHORIZED_RENEW_INTERVAL)
            end
          rescue CommunicationModeSwitch => e
            Log.error("Failed authorization renewal", e, :no_trace)
            self.state = :failed
          rescue Exception => e
            Log.error("Failed authorization renewal", e, :trace)
            @stats["exceptions"].track("renew", e)
            self.state = :failed
          end
        end
      end
      true
    end

    # Update URLs and other data returned from authorization
    # Recreate client if API URL has changed
    #
    # @param [Hash] response containing URLs with keys as symbols
    #
    # @return [TrueClass] always true
    #
    # @raise [CommunicationModeSwitch] changing communication mode
    def update_urls(response)
      mode = response[:mode].to_sym
      raise CommunicationModeSwitch, "RightNet communication mode switching from #{@mode.inspect} to #{mode.inspect}" if @mode && @mode != mode
      @mode = mode
      @shard_id = response[:shard_id].to_i
      if (new_url = response[:router_url]) != @router_url
        Log.info("Updating RightNet router URL to #{new_url.inspect}")
        @router_url = new_url
      end
      if (new_url = response[:api_url]) != @api_url
        Log.info("Updating RightApi URL to #{new_url.inspect}")
        @api_url = new_url
        create_http_client
      end
      true
    end

    # Handle redirect by adjusting URLs to requested location and recreating HTTP client
    #
    # @param [RightScale::BalancedHttpClient::Redirect] exception containing redirect location,
    #   which is required to be a full URL
    #
    # @return [Boolean] whether successfully redirected
    def redirected(exception)
      redirected = false
      location = exception.response.headers[:location]
      if location.nil? || location.empty?
        Log.error("Redirect exception does contain a redirect location")
      else
        new_url = URI.parse(location)
        if new_url.scheme !~ /http/ || new_url.host.empty?
          Log.error("Failed redirect because location is invalid: #{location.inspect}")
        else
          # Apply scheme and host from new URL to existing URL, but not path
          new_url.path = URI.parse(@api_url).path
          @api_url = new_url.to_s
          Log.info("Updating RightApi URL to #{@api_url.inspect} due to redirect to #{location.inspect}")
          @stats["state"].update("redirect")
          create_http_client
          redirected = true
        end
      end
      redirected
    end

    # Reconnect with authorization server by periodically checking health
    # Delay random interval before starting to check to reduce server spiking
    # When again healthy, renew authorization
    #
    # @return [TrueClass] always true
    def reconnect
      unless @reconnecting
        @reconnecting = true
        @stats["reconnects"].update("initiate")
        @reconnect_timer = EM::PeriodicTimer.new(rand(HEALTH_CHECK_INTERVAL)) do
          begin
            @http_client.check_health
            @stats["reconnects"].update("success")
            @reconnect_timer.cancel if @reconnect_timer # only need 'if' for test purposes
            @reconnect_timer = @reconnecting = nil
            renew_authorization(0)
          rescue BalancedHttpClient::NotResponding => e
            @stats["reconnects"].update("no response")
          rescue Exception => e
            Log.error("Failed authorization reconnect", e)
            @stats["reconnects"].update("failure")
           @stats["exceptions"].track("reconnect", e)
          end
          @reconnect_timer.interval = HEALTH_CHECK_INTERVAL if @reconnect_timer
        end
      end
      true
    end

  end # InstanceAuthClient

end # RightScale
